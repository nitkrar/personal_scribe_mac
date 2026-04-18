import Combine
import Foundation
import SeshatCore
import SeshatSession

@MainActor
final class MenuBarSceneModel: ObservableObject {
    @Published var state: SessionState = .idle
    @Published var permissionState: MicrophonePermissionState
    @Published var lastResultText: String? = nil

    private let coordinator: SessionCoordinator
    private let permissionRequester: any MicrophonePermissionRequesting
    private let permissionStateProvider: @MainActor () -> MicrophonePermissionState
    private let clipboardWriter: @MainActor (String) -> Void
    private let openSettings: @MainActor () -> Void
    private let logger: SeshatLogger
    private let onObservationCancelled: (() -> Void)?
    private var observationTask: Task<Void, Never>?
    private(set) var observationTaskCreationCount = 0

    init(
        coordinator: SessionCoordinator,
        permissionRequester: any MicrophonePermissionRequesting,
        permissionStateProvider: @escaping @MainActor () -> MicrophonePermissionState,
        clipboardWriter: @escaping @MainActor (String) -> Void,
        openSettings: @escaping @MainActor () -> Void,
        onObservationCancelled: (() -> Void)? = nil,
        logger: SeshatLogger = SeshatLogger(category: SeshatLogCategory.ui)
    ) {
        self.coordinator = coordinator
        self.permissionRequester = permissionRequester
        self.permissionStateProvider = permissionStateProvider
        self.clipboardWriter = clipboardWriter
        self.openSettings = openSettings
        self.onObservationCancelled = onObservationCancelled
        self.logger = logger
        self.permissionState = permissionStateProvider()
    }

    var recordButton: RecordButtonViewModel {
        RecordButtonViewModel.make(from: state)
    }

    func startObserving() {
        guard observationTask == nil else { return }

        logger.info("Starting coordinator observation")
        observationTaskCreationCount += 1
        let coordinator = coordinator
        observationTask = Task { [weak self, coordinator] in
            guard let self else { return }
            let stream = await coordinator.stateStream()
            for await newState in stream {
                await MainActor.run {
                    self.state = newState
                }
            }
        }
    }

    func handleRecordButtonTap() async {
        logger.info("Record button tapped")

        switch permissionState {
        case .granted:
            await coordinator.toggle()
        case .notYetRequested:
            let granted = await permissionRequester.requestAccess()
            permissionState = granted ? .granted : .denied
            logger.info("Microphone permission request completed: \(granted)")
            if granted {
                await coordinator.toggle()
            }
        case .denied:
            logger.info("Record button tapped while permission denied; ignoring.")
        }
    }

    deinit {
        observationTask?.cancel()
        onObservationCancelled?()
    }
}
