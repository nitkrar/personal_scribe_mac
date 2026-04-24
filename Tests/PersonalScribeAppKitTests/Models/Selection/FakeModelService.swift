import Combine
import Foundation
import PersonalScribeCore

@MainActor
final class FakeModelService: ModelService {
    let registeredModels: [ModelDescriptor]
    @Published private(set) var activeDescriptor: ActiveModelDescriptor
    private(set) var downloadRequests: [String] = []
    private var downloadedModelIDs: Set<String>

    init(
        registeredModels: [ModelDescriptor] = BuiltInModelCatalog.registeredModels,
        activeDescriptor: ActiveModelDescriptor = BuiltInModelCatalog.defaultActiveDescriptor,
        downloadedModelIDs: Set<String> = []
    ) {
        self.registeredModels = registeredModels
        self.activeDescriptor = activeDescriptor
        self.downloadedModelIDs = downloadedModelIDs
    }

    func descriptor(for mode: ModeDescriptor) -> ActiveModelDescriptor {
        let voiceModel = registeredModels.first { $0.id == mode.voiceModelID }
            ?? BuiltInModelCatalog.defaultActiveDescriptor.voiceModel
        return ActiveModelDescriptor(
            voiceModel: voiceModel,
            aiModelID: mode.aiModelID
        )
    }

    func setActive(_ descriptor: ActiveModelDescriptor) async throws {
        guard let canonical = registeredModels.first(where: { $0.id == descriptor.voiceModel.id }) else {
            throw ModelSelectionError.unknownVoiceModelID(descriptor.voiceModel.id)
        }

        activeDescriptor = ActiveModelDescriptor(
            voiceModel: canonical,
            aiModelID: descriptor.aiModelID
        )
    }

    func setActiveVoiceModel(_ id: String) async throws {
        guard let voiceModel = registeredModels.first(where: { $0.id == id }) else {
            throw ModelSelectionError.unknownVoiceModelID(id)
        }

        activeDescriptor = ActiveModelDescriptor(
            voiceModel: voiceModel,
            aiModelID: activeDescriptor.aiModelID
        )
    }

    func isDownloaded(_ descriptor: ModelDescriptor) -> Bool {
        downloadedModelIDs.contains(descriptor.id)
    }

    func download(_ descriptor: ModelDescriptor) async throws {
        downloadRequests.append(descriptor.id)
        downloadedModelIDs.insert(descriptor.id)
    }
}
