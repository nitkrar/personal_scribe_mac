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

    init(
        coordinator: SessionCoordinator,
        permissionRequester: any MicrophonePermissionRequesting,
        permissionStateProvider: @escaping @MainActor () -> MicrophonePermissionState,
        clipboardWriter: @escaping @MainActor (String) -> Void,
        openSettings: @escaping @MainActor () -> Void,
        logger: SeshatLogger = SeshatLogger(category: SeshatLogCategory.ui)
    ) {
        self.coordinator = coordinator
        self.permissionRequester = permissionRequester
        self.permissionStateProvider = permissionStateProvider
        self.clipboardWriter = clipboardWriter
        self.openSettings = openSettings
        self.logger = logger
        self.permissionState = permissionStateProvider()
    }

    func startObserving() {}

    func handleRecordButtonTap() async {
        logger.info("Record button tapped")

        switch permissionState {
        case .granted:
            return
        case .notYetRequested:
            let granted = await permissionRequester.requestAccess()
            permissionState = granted ? .granted : .denied
            logger.info("Microphone permission request completed: \(granted)")
        case .denied:
            logger.info("Record button tapped while permission denied; ignoring.")
        }
    }
}
