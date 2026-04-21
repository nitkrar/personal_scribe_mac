import Combine
import Foundation
import PersonalScribeCore

@MainActor
public final class DefaultModelService: ModelService {
    public static let preferenceKey = "ActiveModelDescriptor"

    public let registeredModels: [ModelDescriptor]
    @Published public private(set) var activeDescriptor: ActiveModelDescriptor
    @Published public private(set) var downloadStates: [String: ModelDownloadState]

    private let selectionPreference: Preference<ActiveModelDescriptor>
    private let isDownloadedHandler: @Sendable (ModelDescriptor) -> Bool
    private let downloadHandler: @Sendable (
        ModelDescriptor,
        @escaping @Sendable (ModelDownloadProgress) -> Void
    ) async throws -> Void
    private let logger: PersonalScribeLogger

    public convenience init(
        storageLocator: any StorageLocator = AppConfig.liveStorageLocator(),
        defaults: UserDefaults = .standard,
        logger: PersonalScribeLogger = PersonalScribeLogger(category: PersonalScribeLogCategory.session)
    ) {
        let provider = ModelBoundTranscriberProvider(storageLocator: storageLocator)
        let selectionPreference = Preference<ActiveModelDescriptor>(
            key: Self.preferenceKey,
            default: BuiltInModelCatalog.defaultActiveDescriptor,
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
        logger: PersonalScribeLogger = PersonalScribeLogger(category: PersonalScribeLogCategory.session)
    ) {
        self.selectionPreference = selectionPreference
        self.registeredModels = registeredModels
        self.isDownloadedHandler = isDownloaded
        self.downloadHandler = download
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
        try await downloadHandler(canonical, progress)
    }
}

private extension DefaultModelService {
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
