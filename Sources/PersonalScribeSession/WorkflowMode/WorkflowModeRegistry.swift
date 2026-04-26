import Foundation
import PersonalScribeCore

/// Owns the user's workflow-mode state (per L21 of #078): list of
/// registered modes (built-ins + custom), active mode tracking, validation
/// on save, and persistence delegation to a `WorkflowModeStoring` seam.
///
/// Distinct from `ActiveModelService` (active per-Kind descriptor); the
/// registry tracks active **mode** only.
///
/// Validation fires at every mutation site that adds or selects a mode
/// (per L15). The set of currently-available `ModelKind` values is
/// supplied via a closure so the registry stays decoupled from
/// `ActiveModelService`.
///
/// Built-in modes: only `WorkflowMode.dictation` today. New
/// built-ins land as additions to `builtInModes` here, not via the store.
public final class WorkflowModeRegistry: @unchecked Sendable {
    public static let builtInModes: [WorkflowMode] = [.dictation]

    private let lock = NSLock()
    private let store: any WorkflowModeStoring
    private let availableKindsProvider: @Sendable () -> Set<ModelKind>
    private var document: WorkflowModeDocument

    public init(
        store: any WorkflowModeStoring,
        availableKindsProvider: @escaping @Sendable () -> Set<ModelKind>
    ) throws {
        self.store = store
        self.availableKindsProvider = availableKindsProvider
        self.document = try store.load()
    }

    /// All modes the user can pick from: built-ins + custom.
    public var allModes: [WorkflowMode] {
        lock.withLock {
            Self.builtInModes + document.customModes
        }
    }

    /// Currently-active mode. Falls back to the built-in `.dictation`
    /// if no `activeModeID` is persisted, or if the persisted ID no
    /// longer resolves to a known mode.
    public var activeMode: WorkflowMode {
        lock.withLock {
            resolveActiveLocked()
        }
    }

    /// Set the active mode by ID. Validates the resolved recipe before
    /// writing. Throws on unknown ID or invalid recipe.
    public func setActive(id: String) throws {
        try lock.withLock {
            guard let mode = resolveModeLocked(id: id) else {
                throw WorkflowModeRegistryError.unknownMode(id)
            }
            try WorkflowModeValidator.validate(
                mode,
                availableKinds: availableKindsProvider()
            )
            document.activeModeID = id
            try store.save(document)
        }
    }

    /// Save (insert or update) a custom mode. Validates before writing.
    /// Built-in IDs cannot be overwritten — throws
    /// `.builtInIDReserved(...)`.
    public func saveCustom(_ mode: WorkflowMode) throws {
        try lock.withLock {
            if Self.builtInModes.contains(where: { $0.id == mode.id }) {
                throw WorkflowModeRegistryError.builtInIDReserved(mode.id)
            }
            try WorkflowModeValidator.validate(
                mode,
                availableKinds: availableKindsProvider()
            )
            if let index = document.customModes.firstIndex(where: { $0.id == mode.id }) {
                document.customModes[index] = mode
            } else {
                document.customModes.append(mode)
            }
            try store.save(document)
        }
    }

    /// Re-validate the currently-active mode against a fresh
    /// `availableKinds` snapshot (per L15, #078.28). Called by
    /// `SessionCoordinator` immediately before starting capture so a
    /// model that became unavailable since `setActive(...)` ran (e.g.
    /// the user deleted it from AI Models tab) is caught before audio
    /// flows.
    ///
    /// - Parameter availableKinds: kinds for which `ActiveModelService`
    ///   currently has an active descriptor. Passed in by the caller
    ///   so this stays a pure validator (no `ActiveModelService`
    ///   coupling here).
    /// - Returns: the validated active mode, ready to be passed to
    ///   `RecipeBuilder`.
    /// - Throws: `WorkflowModeValidationError` on the first rule
    ///   violation. Caller surfaces a descriptive error and aborts the
    ///   session.
    public func validateActiveForSessionStart(
        availableKinds: Set<ModelKind>
    ) throws -> WorkflowMode {
        let mode = activeMode
        try WorkflowModeValidator.validate(mode, availableKinds: availableKinds)
        return mode
    }

    /// Remove a custom mode by ID. If the deleted mode was active, the
    /// active selection falls back to the built-in `.dictation`.
    public func deleteCustom(id: String) throws {
        try lock.withLock {
            document.customModes.removeAll { $0.id == id }
            if document.activeModeID == id {
                document.activeModeID = WorkflowMode.dictation.id
            }
            try store.save(document)
        }
    }

    // MARK: - Internals (lock-held)

    private func resolveActiveLocked() -> WorkflowMode {
        if let id = document.activeModeID, let mode = resolveModeLocked(id: id) {
            return mode
        }
        return .dictation
    }

    private func resolveModeLocked(id: String) -> WorkflowMode? {
        if let builtIn = Self.builtInModes.first(where: { $0.id == id }) {
            return builtIn
        }
        return document.customModes.first(where: { $0.id == id })
    }
}

public enum WorkflowModeRegistryError: Error, Equatable {
    case unknownMode(String)
    case builtInIDReserved(String)
}
