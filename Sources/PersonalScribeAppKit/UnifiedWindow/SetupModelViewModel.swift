import Combine
import Foundation
import PersonalScribeCore
import PersonalScribeSession

@MainActor
final class SetupModelViewModel: ObservableObject {
    let recommendedModel: ModelDescriptor
    let models: [ModelDescriptor]

    private let service: ActiveModelService
    private let prepareActiveModel: @MainActor () async -> Void
    private let showAllModelsAction: @MainActor () -> Void
    private var serviceObservation: AnyCancellable?

    init(
        service: ActiveModelService,
        physicalMemoryBytes: Int64 = Int64(ProcessInfo.processInfo.physicalMemory),
        prepareActiveModel: @escaping @MainActor () async -> Void,
        showAllModels: @escaping @MainActor () -> Void
    ) {
        self.service = service
        self.prepareActiveModel = prepareActiveModel
        self.showAllModelsAction = showAllModels
        self.models = service.visibleModels(kind: .asr)
        self.recommendedModel = DefaultModelSelectionPolicy.recommendedDefault(
            physicalMemoryBytes: physicalMemoryBytes,
            lightweight: BuiltInModelCatalog.parakeetTDTCTC110M,
            baseline: BuiltInModelCatalog.parakeetTDT06Bv2
        )
        serviceObservation = service.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    var selectedModel: ModelDescriptor {
        service.activeDescriptor(for: .asr) ?? recommendedModel
    }

    var selectedState: ModelDownloadState? {
        service.downloadStates[selectedModel.id]
    }

    var isReady: Bool {
        selectedState?.phase == .ready
    }

    func appear() async {
        service.refresh()
        guard !isReady else { return }
        await prepareActiveModel()
    }

    func select(_ descriptor: ModelDescriptor) {
        service.setActive(descriptor, forKind: .asr)
    }

    func showAllModels() {
        showAllModelsAction()
    }
}
