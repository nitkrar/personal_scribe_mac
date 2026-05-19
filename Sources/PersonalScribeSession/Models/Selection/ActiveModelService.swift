import Combine
import Foundation
import PersonalScribeCore

/// Per-`ModelKind` active-model state holder.
///
/// Phase-3 step #024.10 refactor: replaces the prior single-value
/// `ActiveModelDescriptor` with a per-kind `[ModelKind: String]` map
/// (model id values, looked up against `registeredModels`). The
/// recording pipeline always reads `.asr`; future adapters (streaming
/// ASR, diarization, TTS) read their own kind.
@MainActor
public final class ActiveModelService: ObservableObject {
    /// UserDefaults key for the per-kind active-model id map. The pre-
    /// refactor `ActiveModelDescriptor` key (`"ActiveModelDescriptor"`)
    /// is intentionally orphaned — pre-dogfood, no migration. Fresh
    /// installs (and existing dogfood machines) seed via the RAM-aware
    /// default below.
    public static let preferenceKey = "ActiveModelIDs"

    /// Headroom on top of `ModelDescriptor.approximateSizeBytes` to
    /// cover the staging directory + CoreML compilation. Keep in sync
    /// with the documented Stage B contract (200 MB).
    public static let downloadDiskSpaceBufferBytes: Int64 = 200 * 1024 * 1024

    /// Live `diskSpaceProvider` used by the convenience initializer.
    /// Reads the volume's "available for important usage" capacity,
    /// which respects APFS purgeable space.
    public static let liveDiskSpaceProvider: @Sendable (URL) -> Int64? = { url in
        // Walk up to the first existing ancestor so that a not-yet-
        // created models directory still resolves to a valid volume.
        var candidate = url.standardizedFileURL
        while !FileManager.default.fileExists(atPath: candidate.path) {
            let parent = candidate.deletingLastPathComponent().standardizedFileURL
            if parent == candidate { break }
            candidate = parent
        }
        let values = try? candidate.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        if let bytes = values?.volumeAvailableCapacityForImportantUsage {
            return Int64(bytes)
        }
        return nil
    }

    public let registeredModels: [ModelDescriptor]
    @Published public private(set) var activeModelIDs: [ModelKind: String]
    @Published public private(set) var whisperAdapterFilter: WhisperAdapterFilter
    @Published public private(set) var downloadStates: [String: ModelDownloadState]

    private let activeIDsPreference: Preference<[ModelKind: String]>
    private let whisperAdapterFilterPreference: Preference<WhisperAdapterFilter>
    private let isDownloadedHandler: @Sendable (ModelDescriptor) -> Bool
    private let downloadHandler: @Sendable (
        ModelDescriptor,
        @escaping @Sendable (ModelDownloadProgress) -> Void
    ) async throws -> Void
    private let removeDownloadedHandler: @Sendable (ModelDescriptor) throws -> Void
    private let evictHandler: @Sendable (ModelDescriptor) -> Void
    private let modelsDirectoryProvider: @Sendable () -> URL?
    private let diskSpaceProvider: @Sendable (URL) -> Int64?
    private let chipFamilyProvider: @Sendable () -> ChipFamily
    private let logger: PersonalScribeLogger

    /// Hook fired after `setActive` succeeds. The composition root wires
    /// it to `SessionCoordinator.prepareTranscriber()` so the new active
    /// model is warmed at activate-time rather than on next app launch.
    /// Optional + nullable by default — tests that don't care about
    /// post-setActive side effects don't need to wire anything.
    public var onSetActive: (@Sendable () async -> Void)?

    public convenience init(
        storageLocator: any StorageLocator = AppConfig.liveStorageLocator(),
        defaults: UserDefaults = .standard,
        physicalMemoryBytes: Int64 = Int64(ProcessInfo.processInfo.physicalMemory),
        logger: PersonalScribeLogger
    ) {
        let provider = ModelBoundProcessorProvider(
            storageLocator: storageLocator,
            logger: logger
        )

        // #016: RAM-aware first-launch default. The Preference layer's
        // `default:` is only consulted when no value is persisted, so
        // consulting the RAM probe here affects the fresh-install case
        // only. Any subsequent launch reads the persisted user choice
        // and ignores this default.
        let recommendedVoiceModel = DefaultModelSelectionPolicy.recommendedDefault(
            physicalMemoryBytes: physicalMemoryBytes,
            lightweight: BuiltInModelCatalog.parakeetTDTCTC110M,
            baseline: BuiltInModelCatalog.parakeetTDT06Bv2
        )
        let recommendedDefault: [ModelKind: String] = [
            .asr: recommendedVoiceModel.id,
            .streamingASR: BuiltInModelCatalog.parakeetEou160ms.id,
        ]
        let activeIDsPreference = Preference<[ModelKind: String]>(
            key: Self.preferenceKey,
            default: recommendedDefault,
            defaults: defaults
        )
        let whisperAdapterFilterPreference = WhisperAdapterFilter.preference(defaults: defaults)

        self.init(
            activeIDsPreference: activeIDsPreference,
            whisperAdapterFilterPreference: whisperAdapterFilterPreference,
            registeredModels: BuiltInModelCatalog.registeredModels,
            isDownloaded: { descriptor in
                provider.isDownloaded(descriptor)
            },
            download: { descriptor, progress in
                try await provider.download(descriptor, progress: progress)
            },
            removeDownloaded: { descriptor in
                try provider.removeDownloadedFiles(descriptor)
            },
            evict: { descriptor in
                provider.evict(descriptor)
            },
            modelsDirectoryProvider: { storageLocator.url(for: .models) },
            diskSpaceProvider: Self.liveDiskSpaceProvider,
            chipFamily: ChipFamily.current,
            logger: logger
        )
    }

    init(
        activeIDsPreference: Preference<[ModelKind: String]>,
        whisperAdapterFilterPreference: Preference<WhisperAdapterFilter>? = nil,
        registeredModels: [ModelDescriptor] = BuiltInModelCatalog.registeredModels,
        isDownloaded: @escaping @Sendable (ModelDescriptor) -> Bool,
        download: @escaping @Sendable (
            ModelDescriptor,
            @escaping @Sendable (ModelDownloadProgress) -> Void
        ) async throws -> Void,
        removeDownloaded: @escaping @Sendable (ModelDescriptor) throws -> Void = { _ in },
        evict: @escaping @Sendable (ModelDescriptor) -> Void = { _ in },
        modelsDirectoryProvider: @escaping @Sendable () -> URL? = { nil },
        diskSpaceProvider: @escaping @Sendable (URL) -> Int64? = { _ in nil },
        chipFamily: @escaping @Sendable () -> ChipFamily = ChipFamily.current,
        logger: PersonalScribeLogger
    ) {
        let resolvedWhisperAdapterFilterPreference = whisperAdapterFilterPreference
            ?? WhisperAdapterFilter.preference(defaults: activeIDsPreference.defaults)
        self.activeIDsPreference = activeIDsPreference
        self.whisperAdapterFilterPreference = resolvedWhisperAdapterFilterPreference
        self.registeredModels = registeredModels
        self.isDownloadedHandler = isDownloaded
        self.downloadHandler = download
        self.removeDownloadedHandler = removeDownloaded
        self.evictHandler = evict
        self.modelsDirectoryProvider = modelsDirectoryProvider
        self.diskSpaceProvider = diskSpaceProvider
        self.chipFamilyProvider = chipFamily
        self.logger = logger
        self._activeModelIDs = Published(
            initialValue: Self.resolveInitialActiveIDs(
                activeIDsPreference: activeIDsPreference,
                registeredModels: registeredModels,
                chipFamily: chipFamily(),
                logger: logger
            )
        )
        self._whisperAdapterFilter = Published(
            initialValue: resolvedWhisperAdapterFilterPreference.resolve()
        )
        self._downloadStates = Published(
            initialValue: Self.initialDownloadStates(
                registeredModels: registeredModels,
                isDownloaded: isDownloaded
            )
        )
    }

    /// Look up the currently-active descriptor for `kind`. Returns nil
    /// when nothing is active for that kind.
    public func activeDescriptor(for kind: ModelKind) -> ModelDescriptor? {
        guard let id = activeModelIDs[kind] else { return nil }
        guard let descriptor = registeredModels.first(where: { $0.id == id }) else {
            return nil
        }
        guard canActivate(descriptor) else {
            return nil
        }
        return descriptor
    }

    /// Activate `descriptor` for its `kind`. Evicts any previously
    /// active descriptor of the same kind from the provider's adapter
    /// cache so its loaded CoreML weights are released. Persists.
    /// Fires `onSetActive` so the composition root can prepare/warm
    /// the new active descriptor's adapter (load weights at activate
    /// time rather than at download time — see #078 follow-up).
    public func setActive(_ descriptor: ModelDescriptor) {
        guard canActivate(descriptor) else {
            logger.error(
                "Rejected active-model selection unsupported on this Mac: \(descriptor.id)"
            )
            return
        }
        let previousID = activeModelIDs[descriptor.kind]
        var updated = activeModelIDs
        updated[descriptor.kind] = descriptor.id
        activeModelIDs = updated
        activeIDsPreference.persist(updated)
        if let previousID, previousID != descriptor.id,
           let previous = registeredModels.first(where: { $0.id == previousID })
        {
            evictHandler(previous)
        }
        Task { @MainActor [weak self] in
            await self?.onSetActive?()
        }
    }

    /// Filter `registeredModels` for UI. Returns only descriptors whose
    /// kind is enabled today. Optional `kind:` narrows further.
    public func enabledModels(kind: ModelKind? = nil) -> [ModelDescriptor] {
        registeredModels.filter { d in
            d.kind.isEnabled && canActivate(d) && (kind == nil || d.kind == kind)
        }
    }

    /// UI-selectable subset of `enabledModels`. Keeps the catalog and
    /// runtime resolution untouched; only selection surfaces honor the
    /// user's Whisper adapter visibility preference.
    public func visibleModels(kind: ModelKind? = nil) -> [ModelDescriptor] {
        enabledModels(kind: kind).filter { whisperAdapterFilter.includes($0) }
    }

    public func isVisibleModel(_ descriptor: ModelDescriptor) -> Bool {
        descriptor.kind.isEnabled
            && canActivate(descriptor)
            && whisperAdapterFilter.includes(descriptor)
    }

    public func setWhisperAdapterFilter(_ filter: WhisperAdapterFilter) {
        guard whisperAdapterFilter != filter else { return }
        whisperAdapterFilter = filter
        whisperAdapterFilterPreference.persist(filter)
    }

    func canActivate(_ descriptor: ModelDescriptor) -> Bool {
        Self.canActivate(descriptor, chipFamily: chipFamilyProvider())
    }

    /// Kinds for which an active descriptor exists AND its artifacts
    /// are downloaded (`.ready`). Used by `WorkflowModeValidator` to
    /// reject *unpinned* modes whose required kind has no usable model.
    /// Pinned modes (#090) bypass this check via the validator's
    /// `registeredDescriptors:` rule.
    public func availableKinds() -> Set<ModelKind> {
        var kinds: Set<ModelKind> = []
        for kind in ModelKind.allCases where kind.isEnabled {
            guard let descriptor = activeDescriptor(for: kind) else {
                continue
            }
            if downloadStates[descriptor.id]?.phase == .ready {
                kinds.insert(kind)
            }
        }
        return kinds
    }

    public func isDownloaded(_ descriptor: ModelDescriptor) -> Bool {
        guard let canonical = registeredModels.first(where: { $0.id == descriptor.id }) else {
            return false
        }
        return isDownloadedHandler(canonical)
    }

    /// Download `descriptor`'s artifacts. Never touches the active
    /// selection. Idempotent — a no-op publish of `.ready` when already
    /// on disk. Progress is ingested into `downloadStates` internally
    /// (no external progress closure) so `@ObservedObject` subscribers
    /// see `.downloading` / `.loading` / `.ready` phases flow through
    /// without a separate observer wired at the call site.
    public func download(_ descriptor: ModelDescriptor) async throws {
        let canonical = try canonicalVoiceModel(for: descriptor.id)

        if isDownloaded(canonical) {
            publishDownloadState(
                ModelDownloadState(
                    descriptorId: canonical.id,
                    phase: .ready,
                    fractionCompleted: 1
                )
            )
            return
        }

        try ensureSufficientDiskSpace(for: canonical)
        do {
            try await downloadHandler(canonical) { [weak self] progress in
                Task { @MainActor [weak self] in
                    self?.ingest(progress: progress, for: canonical)
                }
            }
        } catch {
            publishDownloadState(
                ModelDownloadState(
                    descriptorId: canonical.id,
                    phase: .failed(message: String(describing: error)),
                    fractionCompleted: 0
                )
            )
            throw error
        }
        publishDownloadState(
            ModelDownloadState(
                descriptorId: canonical.id,
                phase: .ready,
                fractionCompleted: 1
            )
        )
    }

    /// Ticket #024: remove `descriptor`'s on-disk artifacts and flip the
    /// published download-state back to `.notDownloaded`. No confirmation
    /// gate, no last-model rule, no active-model check — the caller owns
    /// any policy. Active selection is intentionally left untouched; if
    /// the deleted model happened to be active, the next `setActive`
    /// will re-download it via the normal path.
    ///
    /// On removal failure (e.g. files held open by the active adapter,
    /// permission denied), publishes a `.failed(message:)` state so the
    /// row chip surfaces the error before re-throwing. Without that
    /// publish, the silent `try?` at the call site leaves the user with
    /// no feedback when delete fails.
    public func removeDownloaded(_ descriptor: ModelDescriptor) throws {
        let canonical = try canonicalVoiceModel(for: descriptor.id)
        do {
            try removeDownloadedHandler(canonical)
        } catch {
            publishDownloadState(
                ModelDownloadState(
                    descriptorId: canonical.id,
                    phase: .failed(message: "Delete failed: \(error.localizedDescription)"),
                    fractionCompleted: 0
                )
            )
            throw error
        }
        publishDownloadState(
            ModelDownloadState(
                descriptorId: canonical.id,
                phase: .notDownloaded,
                fractionCompleted: 0
            )
        )
    }

    /// Re-sync `downloadStates` against the injected disk-presence
    /// probe for every registered model. Flips `.ready` ↔ `.notDownloaded`
    /// to match disk truth; preserves in-flight `.downloading` / `.loading`
    /// and explicit `.failed` states so UI refreshes can't stomp a live
    /// download or quietly clear an error the user hasn't retried.
    ///
    /// Idempotent when disk matches published state — no publish is
    /// emitted, so `@ObservedObject` subscribers don't re-render.
    ///
    /// Ticket #039: AIModelsTab's `.onAppear` calls this so a model
    /// that appeared (or disappeared) from disk while the tab was
    /// off-screen flips its chip on re-entry without a window restart.
    public func refresh() {
        for descriptor in registeredModels {
            let currentPhase = downloadStates[descriptor.id]?.phase ?? .notDownloaded
            switch currentPhase {
            case .downloading, .loading, .failed:
                // Preserve: an in-flight or errored state reflects
                // intent that a disk probe cannot reason about.
                continue
            case .ready, .notDownloaded:
                let isOnDisk = isDownloadedHandler(descriptor)
                let desiredPhase: ModelDownloadState.Phase = isOnDisk ? .ready : .notDownloaded
                guard desiredPhase != currentPhase else { continue }
                publishDownloadState(
                    ModelDownloadState(
                        descriptorId: descriptor.id,
                        phase: desiredPhase,
                        fractionCompleted: isOnDisk ? 1 : 0
                    )
                )
            }
        }
    }
}

private extension ActiveModelService {
    /// Stage B — disk-space precheck.
    ///
    /// Compares `descriptor.approximateSizeBytes + downloadDiskSpaceBufferBytes`
    /// against the volume's available capacity for the models directory.
    /// If the provider cannot resolve a directory URL or returns `nil`,
    /// the precheck is skipped (fail-open): we do not want to block a
    /// download on a probing failure. When the probe succeeds and the
    /// volume is short of required bytes, publish a `.failed(message:)`
    /// download state and throw `ModelSelectionError.insufficientDiskSpace`.
    func ensureSufficientDiskSpace(for descriptor: ModelDescriptor) throws {
        guard let modelsDirectory = modelsDirectoryProvider() else {
            return
        }
        guard let availableBytes = diskSpaceProvider(modelsDirectory) else {
            return
        }
        let requiredBytes = descriptor.approximateSizeBytes + Self.downloadDiskSpaceBufferBytes
        guard availableBytes < requiredBytes else {
            return
        }

        let error = ModelSelectionError.insufficientDiskSpace(
            required: requiredBytes,
            available: availableBytes
        )
        publishDownloadState(
            ModelDownloadState(
                descriptorId: descriptor.id,
                phase: .failed(message: diskSpaceFailureMessage(
                    for: descriptor,
                    required: requiredBytes,
                    available: availableBytes
                )),
                fractionCompleted: 0
            )
        )
        throw error
    }

    func diskSpaceFailureMessage(
        for descriptor: ModelDescriptor,
        required: Int64,
        available: Int64
    ) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        let requiredStr = formatter.string(fromByteCount: required)
        let availableStr = formatter.string(fromByteCount: available)
        return "Not enough disk space to download \(descriptor.displayName). Needs \(requiredStr), \(availableStr) available."
    }

    func ingest(progress: ModelDownloadProgress, for descriptor: ModelDescriptor) {
        let mappedPhase: ModelDownloadState.Phase
        switch progress.phase {
        case .idle:
            // `.idle` is a steady-state, pre-download tick; do not perturb
            // a `.notDownloaded` / `.ready` cell.
            return
        case .downloading:
            mappedPhase = .downloading
        case .loading:
            mappedPhase = .loading
        case .finished:
            mappedPhase = .ready
        }

        publishDownloadState(
            ModelDownloadState(
                descriptorId: descriptor.id,
                phase: mappedPhase,
                fractionCompleted: progress.fractionCompleted
            )
        )
    }

    func publishDownloadState(_ state: ModelDownloadState) {
        var mutableStates = downloadStates
        mutableStates[state.descriptorId] = state
        downloadStates = mutableStates
    }

    static func initialDownloadStates(
        registeredModels: [ModelDescriptor],
        isDownloaded: (ModelDescriptor) -> Bool
    ) -> [String: ModelDownloadState] {
        var states: [String: ModelDownloadState] = [:]
        for descriptor in registeredModels {
            let phase: ModelDownloadState.Phase = isDownloaded(descriptor) ? .ready : .notDownloaded
            let fraction: Double = isDownloaded(descriptor) ? 1 : 0
            states[descriptor.id] = ModelDownloadState(
                descriptorId: descriptor.id,
                phase: phase,
                fractionCompleted: fraction
            )
        }
        return states
    }

    func canonicalVoiceModel(for id: String) throws -> ModelDescriptor {
        guard let descriptor = registeredModels.first(where: { $0.id == id }) else {
            throw ModelSelectionError.unknownVoiceModelID(id)
        }
        return descriptor
    }

    /// Read the persisted active-id map and rewrite any entry that no
    /// longer reference a registered model. If pruning happens, the
    /// preference is rewritten so the next launch sees the cleaned map.
    static func resolveInitialActiveIDs(
        activeIDsPreference: Preference<[ModelKind: String]>,
        registeredModels: [ModelDescriptor],
        chipFamily: ChipFamily,
        logger: PersonalScribeLogger
    ) -> [ModelKind: String] {
        let stored = activeIDsPreference.resolve()
        let registeredByID = Dictionary(uniqueKeysWithValues: registeredModels.map { ($0.id, $0) })

        var cleaned: [ModelKind: String] = [:]
        for (kind, id) in stored {
            if let descriptor = registeredByID[id] {
                guard canActivate(descriptor, chipFamily: chipFamily) else {
                    logger.error(
                        "Stored active-model id unsupported on \(chipFamily.rawValue): \(id)"
                    )
                    continue
                }
                cleaned[kind] = id
            } else {
                logger.error(
                    "Stored active-model id no longer registered for \(kind.rawValue): \(id)",
                    error: ModelSelectionError.storedSelectionNoLongerRegistered(id)
                )
            }
        }

        for (kind, id) in activeIDsPreference.default where cleaned[kind] == nil {
            guard
                let descriptor = registeredByID[id],
                canActivate(descriptor, chipFamily: chipFamily)
            else {
                continue
            }
            cleaned[kind] = id
        }

        if cleaned != stored {
            activeIDsPreference.persist(cleaned)
        }

        return cleaned
    }

    static func canActivate(_ descriptor: ModelDescriptor, chipFamily: ChipFamily) -> Bool {
        descriptor.isEnabled && chipFamilyAllows(descriptor, chipFamily: chipFamily)
    }

    static func chipFamilyAllows(_ descriptor: ModelDescriptor, chipFamily: ChipFamily) -> Bool {
        descriptor.requiredChipFamily == nil
            || descriptor.requiredChipFamily == chipFamily
            || (descriptor.requiredChipFamily == .m2OrLater && chipFamily == .m2OrLater)
    }
}
