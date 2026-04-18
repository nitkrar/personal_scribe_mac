import AppKit
import SwiftUI
import SeshatCore
import SeshatSession

@MainActor
struct SeshatApp: App {
    @StateObject private var model: MenuBarSceneModel

    init(
        coordinator: SessionCoordinator,
        permissionRequester: any MicrophonePermissionRequesting,
        permissionStateProvider: (@MainActor () -> MicrophonePermissionState)? = nil,
        logger: SeshatLogger = SeshatLogger(category: SeshatLogCategory.ui)
    ) {
        let initialPermissionState: MicrophonePermissionState
        if let permissionStateProvider {
            initialPermissionState = permissionStateProvider()
        } else if let permissionRequester = permissionRequester as? AppKitMicrophonePermissionRequester {
            initialPermissionState = permissionRequester.currentState()
        } else {
            initialPermissionState = .notYetRequested
        }

        _model = StateObject(
            wrappedValue: MenuBarSceneModel(
                coordinator: coordinator,
                permissionRequester: permissionRequester,
                permissionStateProvider: { initialPermissionState },
                clipboardWriter: { text in
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(text, forType: .string)
                },
                openSettings: {
                    guard let url = URL(
                        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
                    ) else {
                        return
                    }

                    NSWorkspace.shared.open(url)
                },
                logger: logger
            )
        )
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarScene(model: model)
        } label: {
            Image(systemName: model.statusIcon.systemImageName)
                .accessibilityLabel(model.statusIcon.accessibilityLabel)
        }
    }
}
