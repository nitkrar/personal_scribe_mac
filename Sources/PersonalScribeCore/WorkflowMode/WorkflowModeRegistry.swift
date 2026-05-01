import Foundation

/// Owns the user's workflow-mode state (#078 L21 + #089 split).
///
/// State surfaces:
/// - **Default mode** (persisted, `WorkflowModeDocument.defaultModeID`)
///   — the user's chosen launch mode. Resolves to `WorkflowMode.dictation`
///   when unset / stale.
/// - **Current mode** (runtime, `inMemoryCurrentID`) — the mode the
///   next session start will use. Switched by menu-bar / pill switcher
///   / per-mode hotkey. Resets to `defaultMode` at app launch
///   (#089 L-5, L-6).
///
/// Both reads happen under the existing `NSLock` (#089 L-7 — NOT
/// `@MainActor`-isolated; same access pattern as the legacy
/// `activeMode`).
///
/// Validation fires at every mutation site that adds or selects a mode
/// (per L15). The set of currently-available `ModelKind` values is
/// supplied via a closure so the registry stays decoupled from
/// `ActiveModelService`.
///
/// Built-in modes: only `WorkflowMode.dictation` today. The built-in
/// is **never rendered** in the Modes UI; it acts as the fallback
/// recipe when no custom default is set (#089 L-1, L-2).
public final class WorkflowModeRegistry: @unchecked Sendable {
    public static let builtInModes: [WorkflowMode] = [.dictation]

    private let lock = NSLock()
    private let store: any WorkflowModeStoring
    private let availableKindsProvider: @Sendable () -> Set<ModelKind>
    private let registeredDescriptorsProvider: @Sendable () -> [ModelDescriptor]
    private var document: WorkflowModeDocument
    private var inMemoryCurrentID: String?

    private var defaultModeContinuations: [UUID: AsyncStream<WorkflowMode>.Continuation] = [:]
    private var currentModeContinuations: [UUID: AsyncStream<WorkflowMode>.Continuation] = [:]
    private var customModesContinuations: [UUID: AsyncStream<[WorkflowMode]>.Continuation] = [:]

    public init(
        store: any WorkflowModeStoring,
        availableKindsProvider: @escaping @Sendable () -> Set<ModelKind>,
        registeredDescriptorsProvider: @escaping @Sendable () -> [ModelDescriptor] = {
            BuiltInModelCatalog.registeredModels
        }
    ) throws {
        self.store = store
        self.availableKindsProvider = availableKindsProvider
        self.registeredDescriptorsProvider = registeredDescriptorsProvider
        var loaded = try store.load()
        // #027 — one-time migration: re-mint legacy `custom-{UUID}`
        // ids in the new `{cleanName}-{suffix}` format so transcript
        // rows referencing an orphaned mode can recover a display
        // fallback by splitting the id on `-`. Updates `defaultModeID`
        // when it points at a re-minted entry. Soft-fail the save so
        // init doesn't throw on a transient I/O hiccup.
        if Self.documentNeedsIDMigration(loaded) {
            loaded = Self.migrateLegacyIDs(in: loaded)
            try? store.save(loaded)
        }
        // Stale-ID auto-clear at init (#089 IMPL §H.1): if the persisted
        // defaultModeID points at a mode that no longer exists in
        // customModes, scrub it and persist. Soft-fail the save so init
        // doesn't throw on a transient I/O hiccup; resolve path falls
        // back to .dictation either way.
        if let id = loaded.defaultModeID,
           !loaded.customModes.contains(where: { $0.id == id }) {
            loaded.defaultModeID = nil
            try? store.save(loaded)
        }
        self.document = loaded
    }

    /// True when any custom mode in `document` still uses the pre-#027
    /// `custom-{UUID}` id format. Drives the migration in `init`.
    static func documentNeedsIDMigration(_ document: WorkflowModeDocument) -> Bool {
        document.customModes.contains { WorkflowMode.isLegacyID($0.id) }
    }

    /// Re-mint legacy ids in `document` and remap `defaultModeID` if
    /// it points at a migrated entry. Pure function — no I/O — so
    /// `init` can call `try?` `store.save` once with the result.
    static func migrateLegacyIDs(in document: WorkflowModeDocument) -> WorkflowModeDocument {
        var rewritten = document
        var idMap: [String: String] = [:]
        rewritten.customModes = document.customModes.map { mode in
            guard WorkflowMode.isLegacyID(mode.id) else { return mode }
            let newID = WorkflowMode.makeID(name: mode.name)
            idMap[mode.id] = newID
            return WorkflowMode(
                id: newID,
                name: mode.name,
                glyph: mode.glyph,
                preset: mode.preset,
                hotkey: mode.hotkey,
                pipelineShape: mode.pipelineShape,
                processors: mode.processors,
                captureControllers: mode.captureControllers,
                outputSinks: mode.outputSinks,
                streamingBehavior: mode.streamingBehavior
            )
        }
        if let oldDefault = rewritten.defaultModeID,
           let newDefault = idMap[oldDefault] {
            rewritten.defaultModeID = newDefault
        }
        return rewritten
    }

    // MARK: - Streams

    /// Observable stream of the current mode (#089). Yields the
    /// resolved current mode on subscribe and again whenever
    /// `setCurrent` / `setDefault` (when the changed default is also
    /// the current) / `deleteCustom` / `saveCustom` shifts the
    /// in-memory current.
    public func currentModeStream() -> AsyncStream<WorkflowMode> {
        let id = UUID()
        return AsyncStream { continuation in
            let initial = self.lock.withLock { () -> WorkflowMode in
                self.currentModeContinuations[id] = continuation
                return self.resolveCurrentLocked()
            }
            continuation.onTermination = { [weak self] _ in
                guard let self else { return }
                self.lock.withLock {
                    self.currentModeContinuations[id] = nil
                }
            }
            continuation.yield(initial)
        }
    }

    /// Observable stream of the default mode (#089). Yields on
    /// subscribe + on every `setDefault` / `deleteCustom` (when the
    /// deleted mode was default) / `saveCustom` (when the saved mode
    /// is the default).
    public func defaultModeStream() -> AsyncStream<WorkflowMode> {
        let id = UUID()
        return AsyncStream { continuation in
            let initial = self.lock.withLock { () -> WorkflowMode in
                self.defaultModeContinuations[id] = continuation
                return self.resolveDefaultLocked()
            }
            continuation.onTermination = { [weak self] _ in
                guard let self else { return }
                self.lock.withLock {
                    self.defaultModeContinuations[id] = nil
                }
            }
            continuation.yield(initial)
        }
    }

    /// Observable stream of the custom-mode list (#089). Yields on
    /// subscribe + on every list-changing mutation (save / delete /
    /// reorder).
    public func customModesStream() -> AsyncStream<[WorkflowMode]> {
        let id = UUID()
        return AsyncStream { continuation in
            let initial = self.lock.withLock { () -> [WorkflowMode] in
                self.customModesContinuations[id] = continuation
                return self.document.customModes
            }
            continuation.onTermination = { [weak self] _ in
                guard let self else { return }
                self.lock.withLock {
                    self.customModesContinuations[id] = nil
                }
            }
            continuation.yield(initial)
        }
    }

    private func broadcastDefaultMode() {
        let (mode, continuations) = lock.withLock {
            (resolveDefaultLocked(), Array(defaultModeContinuations.values))
        }
        for continuation in continuations {
            continuation.yield(mode)
        }
    }

    private func broadcastCurrentMode() {
        let (mode, continuations) = lock.withLock {
            (resolveCurrentLocked(), Array(currentModeContinuations.values))
        }
        for continuation in continuations {
            continuation.yield(mode)
        }
    }

    private func broadcastCustomModes() {
        let (modes, continuations) = lock.withLock {
            (document.customModes, Array(customModesContinuations.values))
        }
        for continuation in continuations {
            continuation.yield(modes)
        }
    }

    // MARK: - Reads

    /// All modes the user can pick from: built-ins + custom. The
    /// editor UI shows custom modes only (#089 L-2); this accessor
    /// stays available for non-editor callers (e.g. eager-binding
    /// session lookup) that need to resolve any id.
    public var allModes: [WorkflowMode] {
        lock.withLock {
            Self.builtInModes + document.customModes
        }
    }

    /// User's custom modes only. Editor binds against this list.
    public var customModes: [WorkflowMode] {
        lock.withLock {
            document.customModes
        }
    }

    /// Resolved default mode. Falls back to `WorkflowMode.dictation`
    /// when `defaultModeID` is unset or doesn't resolve to a custom
    /// mode.
    public var defaultMode: WorkflowMode {
        lock.withLock {
            resolveDefaultLocked()
        }
    }

    /// Resolved current mode. Falls back to `defaultMode` when
    /// `inMemoryCurrentID` is unset.
    public var currentMode: WorkflowMode {
        lock.withLock {
            resolveCurrentLocked()
        }
    }

    // MARK: - Mutations

    /// Set the default mode by id. Validates the mode against
    /// `availableKindsProvider()` before persisting (#089 L-9 — invalid
    /// recipes can't be activated). Throws on unknown id (must be a
    /// custom mode) or validation failure.
    public func setDefault(id: String) throws {
        try lock.withLock {
            guard let mode = document.customModes.first(where: { $0.id == id }) else {
                throw WorkflowModeRegistryError.unknownMode(id)
            }
            try WorkflowModeValidator.validate(
                mode,
                availableKinds: availableKindsProvider(),
                registeredDescriptors: registeredDescriptorsProvider()
            )
            document.defaultModeID = id
            try store.save(document)
        }
        broadcastDefaultMode()
        // Default change can shift currentMode when no in-memory current
        // is set (resolveCurrentLocked falls through to default).
        broadcastCurrentMode()
    }

    /// Set the runtime current mode by id. Unknown id is a silent
    /// no-op (caller likely raced a deletion). No validation — the
    /// setDefault path already gated availability; switching current
    /// mid-runtime mirrors the resolved binding the editor already
    /// approved.
    public func setCurrent(id: String) {
        let resolved: Bool = lock.withLock {
            if document.customModes.contains(where: { $0.id == id }) {
                inMemoryCurrentID = id
                return true
            }
            return false
        }
        if resolved {
            broadcastCurrentMode()
        }
    }

    /// Reorder a custom mode entry. `from` and `to` are indices into
    /// `customModes`. Persists the new order.
    public func reorderCustom(from: Int, to: Int) throws {
        try lock.withLock {
            let count = document.customModes.count
            guard from >= 0, from < count, to >= 0, to < count else {
                throw WorkflowModeRegistryError.invalidIndex
            }
            guard from != to else { return }
            let moved = document.customModes.remove(at: from)
            document.customModes.insert(moved, at: to)
            try store.save(document)
        }
        broadcastCustomModes()
    }

    /// Skip-gaps default-name resolver (#089 L-14). Returns
    /// `basename` if no custom mode currently uses it; otherwise
    /// returns `"<basename> N"` where `N` is one greater than the
    /// largest existing suffix (or 2 if only the bare basename is
    /// taken). Skip-gaps means deleting "Notes 2" and creating again
    /// produces "Notes 3", not a re-used "Notes 2".
    public func nextAvailableName(_ basename: String) -> String {
        lock.withLock {
            let prefix = "\(basename) "
            var basenameTaken = false
            var maxSuffix: Int = 0
            for mode in document.customModes {
                if mode.name == basename {
                    basenameTaken = true
                    continue
                }
                if mode.name.hasPrefix(prefix) {
                    let suffix = String(mode.name.dropFirst(prefix.count))
                    if let n = Int(suffix), n > maxSuffix {
                        maxSuffix = n
                    }
                }
            }
            if !basenameTaken && maxSuffix == 0 {
                return basename
            }
            let next = max(maxSuffix, 1) + 1
            return "\(basename) \(next)"
        }
    }

    /// Save (insert or update) a custom mode. Validates before writing.
    /// Built-in IDs cannot be overwritten — throws
    /// `.builtInIDReserved(...)`. Broadcasts the custom-modes stream
    /// + default/current streams when the saved mode happens to be the
    /// active selection (mutation may have changed user-visible state
    /// for those observers).
    public func saveCustom(_ mode: WorkflowMode) throws {
        var defaultChanged = false
        var currentChanged = false
        try lock.withLock {
            if Self.builtInModes.contains(where: { $0.id == mode.id }) {
                throw WorkflowModeRegistryError.builtInIDReserved(mode.id)
            }
            try WorkflowModeValidator.validate(
                mode,
                availableKinds: availableKindsProvider(),
                registeredDescriptors: registeredDescriptorsProvider()
            )
            if let index = document.customModes.firstIndex(where: { $0.id == mode.id }) {
                document.customModes[index] = mode
            } else {
                document.customModes.append(mode)
            }
            try store.save(document)
            defaultChanged = (document.defaultModeID == mode.id)
            currentChanged = (inMemoryCurrentID == mode.id)
        }
        broadcastCustomModes()
        if defaultChanged { broadcastDefaultMode() }
        if currentChanged { broadcastCurrentMode() }
    }

    /// Re-validate the current mode against a fresh `availableKinds`
    /// snapshot (#078.28 + #089 L-8). Called by `SessionCoordinator`
    /// immediately before starting capture so a model that became
    /// unavailable since the user picked the mode (e.g. they deleted
    /// it from AI Models tab) is caught before audio flows.
    ///
    /// - Parameter availableKinds: kinds for which `ActiveModelService`
    ///   currently has an active descriptor. Passed in by the caller
    ///   so this stays a pure validator (no `ActiveModelService`
    ///   coupling here).
    /// - Returns: the validated current mode, ready to be passed to
    ///   `RecipeBuilder`.
    /// - Throws: `WorkflowModeValidationError` on the first rule
    ///   violation. Caller surfaces a descriptive error and aborts the
    ///   session.
    public func validateCurrentForSessionStart(
        availableKinds: Set<ModelKind>
    ) throws -> WorkflowMode {
        let mode = currentMode
        try WorkflowModeValidator.validate(
            mode,
            availableKinds: availableKinds,
            registeredDescriptors: registeredDescriptorsProvider()
        )
        return mode
    }

    /// Remove a custom mode by ID. If the deleted mode was the
    /// default, `defaultModeID` is cleared (resolves to
    /// `.dictation`). If the deleted mode was the in-memory current,
    /// the in-memory current is cleared (resolves to `defaultMode`).
    public func deleteCustom(id: String) throws {
        var defaultChanged = false
        var currentChanged = false
        try lock.withLock {
            let originalCount = document.customModes.count
            document.customModes.removeAll { $0.id == id }
            guard document.customModes.count != originalCount else {
                return
            }
            if document.defaultModeID == id {
                document.defaultModeID = nil
                defaultChanged = true
            }
            if inMemoryCurrentID == id {
                inMemoryCurrentID = nil
                currentChanged = true
            }
            try store.save(document)
        }
        broadcastCustomModes()
        if defaultChanged { broadcastDefaultMode() }
        if currentChanged || defaultChanged {
            // Current resolution depends on default when in-memory current
            // is nil; broadcast unconditionally on either change.
            broadcastCurrentMode()
        }
    }

    // MARK: - Internals (lock-held)

    private func resolveDefaultLocked() -> WorkflowMode {
        if let id = document.defaultModeID,
           let mode = document.customModes.first(where: { $0.id == id }) {
            return mode
        }
        return .dictation
    }

    private func resolveCurrentLocked() -> WorkflowMode {
        if let id = inMemoryCurrentID,
           let mode = document.customModes.first(where: { $0.id == id }) {
            return mode
        }
        return resolveDefaultLocked()
    }
}

public enum WorkflowModeRegistryError: Error, Equatable {
    case unknownMode(String)
    case builtInIDReserved(String)
    case invalidIndex
}
