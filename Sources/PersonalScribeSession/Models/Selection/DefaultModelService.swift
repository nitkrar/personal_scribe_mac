import Combine
import Foundation
import PersonalScribeCore

@MainActor
public final class DefaultModelService: ModelService {
    public static let preferenceKey = "ActiveModelDescriptor"

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
    @Published public private(set) var activeDescriptor: ActiveModelDescriptor
    @Published public private(set) var downloadStates: [String: ModelDownloadState]

    private let selectionPreference: Preference<ActiveModelDescriptor>
    private let isDownloadedHandler: @Sendable (ModelDescriptor) -> Bool
    private let downloadHandler: @Sendable (
        ModelDescriptor,
        @escaping @Sendable (ModelDownloadProgress) -> Void
    ) async throws -> Void
    private let modelsDirectoryProvider: @Sendable () -> URL?
    private let diskSpaceProvider: @Sendable (URL) -> Int64?
    private let logger: PersonalScribeLogger

    public convenience init(
        storageLocator: any StorageLocator = AppConfig.liveStorageLocator(),
        defaults: UserDefaults = .standard,
        physicalMemoryBytes: Int64 = Int64(ProcessInfo.processInfo.physicalMemory),
        logger: PersonalScribeLogger = PersonalScribeLogger(category: PersonalScribeLogCategory.session)
    ) {
        let provider = ModelBoundTranscriberProvider(storageLocator: storageLocator)

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
        let recommendedDefault = ActiveModelDescriptor(
            voiceModel: recommendedVoiceModel,
            aiModelID: BuiltInModelCatalog.defaultActiveDescriptor.aiModelID
        )
        let selectionPreference = Preference<ActiveModelDescriptor>(
            key: Self.preferenceKey,
            default: recommendedDefault,
            defaults: defaults
        )

        self.init(
            selectionPreference: selectionPreference,
            registeredModels: BuiltInModelCatalog.registeredModels,
            isDownloaded: { descriptor in
                provider.isDownloaded(descriptor)
            },
            download: { descriptor, progress in
                try await provider.download(descriptor, progress: progress)
            },
            modelsDirectoryProvider: { storageLocator.url(for: .models) },
            diskSpaceProvider: Self.liveDiskSpaceProvider,
            logger: logger
        )
    }

    init(
        selectionPreference: Preference<ActiveModelDescriptor>,
        registeredModels: [ModelDescriptor] = BuiltInModelCatalog.registeredModels,
        isDownloaded: @escaping @Sendable (ModelDescriptor) -> Bool,
        download: @escaping @Sendable (
            ModelDescriptor,
            @escaping @Sendable (ModelDownloadProgress) -> Void
        ) async throws -> Void,
        modelsDirectoryProvider: @escaping @Sendable () -> URL? = { nil },
        diskSpaceProvider: @escaping @Sendable (URL) -> Int64? = { _ in nil },
        logger: PersonalScribeLogger = PersonalScribeLogger(category: PersonalScribeLogCategory.session)
    ) {
        self.selectionPreference = selectionPreference
        self.registeredModels = registeredModels
        self.isDownloadedHandler = isDownloaded
        self.downloadHandler = download
        self.modelsDirectoryProvider = modelsDirectoryProvider
        self.diskSpaceProvider = diskSpaceProvider
        self.logger = logger
        self._activeDescriptor = Published(
            initialValue: Self.resolveInitialDescriptor(
                selectionPreference: selectionPreference,
                registeredModels: registeredModels,
                logger: logger
            )
        )
        self._downloadStates = Published(
            initialValue: Self.initialDownloadStates(
                registeredModels: registeredModels,
                isDownloaded: isDownloaded
            )
        )
    }

    public func descriptor(for mode: ModeDescriptor) -> ActiveModelDescriptor {
        let voiceModel = registeredModels.first { $0.id == mode.voiceModelID }
            ?? Self.defaultDescriptor(from: registeredModels).voiceModel
        return ActiveModelDescriptor(
            voiceModel: voiceModel,
            aiModelID: mode.aiModelID
        )
    }

    public func setActive(_ descriptor: ActiveModelDescriptor) async throws {
        let canonical = try canonicalDescriptor(for: descriptor)
        let voiceModel = canonical.voiceModel

        if !isDownloaded(voiceModel) {
            try ensureSufficientDiskSpace(for: voiceModel)
            do {
                try await download(voiceModel) { [weak self] progress in
                    Task { @MainActor [weak self] in
                        self?.ingest(progress: progress, for: voiceModel)
                    }
                }
            } catch {
                publishDownloadState(
                    ModelDownloadState(
                        descriptorId: voiceModel.id,
                        phase: .failed(message: String(describing: error)),
                        fractionCompleted: 0
                    )
                )
                throw error
            }
            // Ensure the final state is `.ready` even if the underlying
            // download handler never emitted `.finished` (the contract of
            // `download(_:progress:)` does not require a terminal tick).
            publishDownloadState(
                ModelDownloadState(
                    descriptorId: voiceModel.id,
                    phase: .ready,
                    fractionCompleted: 1
                )
            )
        } else {
            // Model already on disk → guarantee the surface reflects that
            // even if the service was constructed before disk state was
            // truthy for this descriptor.
            publishDownloadState(
                ModelDownloadState(
                    descriptorId: voiceModel.id,
                    phase: .ready,
                    fractionCompleted: 1
                )
            )
        }

        selectionPreference.persist(canonical)
        activeDescriptor = canonical
    }

    public func setActiveVoiceModel(_ id: String) async throws {
        let voiceModel = try canonicalVoiceModel(for: id)
        try await setActive(
            ActiveModelDescriptor(
                voiceModel: voiceModel,
                aiModelID: activeDescriptor.aiModelID
            )
        )
    }

    public func isDownloaded(_ descriptor: ModelDescriptor) -> Bool {
        guard let canonical = registeredModels.first(where: { $0.id == descriptor.id }) else {
            return false
        }
        return isDownloadedHandler(canonical)
    }

    public func download(
        _ descriptor: ModelDescriptor,
        progress: @escaping @Sendable (ModelDownloadProgress) -> Void
    ) async throws {
        let canonical = try canonicalVoiceModel(for: descriptor.id)
        try ensureSufficientDiskSpace(for: canonical)
        try await downloadHandler(canonical, progress)
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

private extension DefaultModelService {
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

    func canonicalDescriptor(
        for descriptor: ActiveModelDescriptor
    ) throws -> ActiveModelDescriptor {
        ActiveModelDescriptor(
            voiceModel: try canonicalVoiceModel(for: descriptor.voiceModel.id),
            aiModelID: descriptor.aiModelID
        )
    }

    func canonicalVoiceModel(for id: String) throws -> ModelDescriptor {
        guard let descriptor = registeredModels.first(where: { $0.id == id }) else {
            throw ModelSelectionError.unknownVoiceModelID(id)
        }
        return descriptor
    }

    static func resolveInitialDescriptor(
        selectionPreference: Preference<ActiveModelDescriptor>,
        registeredModels: [ModelDescriptor],
        logger: PersonalScribeLogger
    ) -> ActiveModelDescriptor {
        let stored = selectionPreference.resolve()

        guard let canonicalVoiceModel = registeredModels.first(where: { $0.id == stored.voiceModel.id }) else {
            logger.error(
                "Stored model selection no longer registered: \(stored.voiceModel.id)",
                error: ModelSelectionError.storedSelectionNoLongerRegistered(stored.voiceModel.id)
            )
            let fallback = defaultDescriptor(from: registeredModels)
            selectionPreference.persist(fallback)
            return fallback
        }

        let canonical = ActiveModelDescriptor(
            voiceModel: canonicalVoiceModel,
            aiModelID: stored.aiModelID
        )

        if canonical != stored {
            selectionPreference.persist(canonical)
        }

        return canonical
    }

    static func defaultDescriptor(from registeredModels: [ModelDescriptor]) -> ActiveModelDescriptor {
        if let descriptor = registeredModels.first(
            where: { $0.id == BuiltInModelCatalog.defaultActiveDescriptor.voiceModel.id }
        ) {
            return ActiveModelDescriptor(
                voiceModel: descriptor,
                aiModelID: BuiltInModelCatalog.defaultActiveDescriptor.aiModelID
            )
        }

        if let descriptor = registeredModels.first {
            return ActiveModelDescriptor(voiceModel: descriptor)
        }

        return BuiltInModelCatalog.defaultActiveDescriptor
    }
}
