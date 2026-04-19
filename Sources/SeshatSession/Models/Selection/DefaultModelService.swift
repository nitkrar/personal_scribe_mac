import Combine
import Foundation
import SeshatCore

@MainActor
public final class DefaultModelService: ModelService {
    public static let preferenceKey = "ActiveModelDescriptor"

    public let registeredModels: [ModelDescriptor]
    @Published public private(set) var activeDescriptor: ActiveModelDescriptor

    private let selectionPreference: Preference<ActiveModelDescriptor>
    private let isDownloadedHandler: @Sendable (ModelDescriptor) -> Bool
    private let downloadHandler: @Sendable (
        ModelDescriptor,
        @escaping @Sendable (ModelDownloadProgress) -> Void
    ) async throws -> Void
    private let logger: SeshatLogger

    public init(
        storageLocator: any StorageLocator = AppConfig.liveStorageLocator(),
        defaults: UserDefaults = .standard,
        logger: SeshatLogger = SeshatLogger(category: SeshatLogCategory.session)
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
        logger: SeshatLogger = SeshatLogger(category: SeshatLogCategory.session)
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

        if !isDownloaded(canonical.voiceModel) {
            try await download(canonical.voiceModel) { _ in }
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
        logger: SeshatLogger
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
