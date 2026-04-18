import AppKit
import SwiftUI
import SeshatCore
import SeshatSession

@main
@MainActor
struct SeshatAppMain: App {
    let coordinator: SessionCoordinator
    let permissionRequester: any MicrophonePermissionRequesting

    @StateObject private var sceneModel: MenuBarSceneModel

    init() {
        let coordinator = AppComposition.sessionCoordinator
        let permissionRequester = AppComposition.makeMicrophonePermissionRequester()

        self.coordinator = coordinator
        self.permissionRequester = permissionRequester
        _sceneModel = StateObject(
            wrappedValue: MenuBarSceneModel(
                coordinator: coordinator,
                permissionRequester: permissionRequester,
                permissionStateProvider: {
                    if let permissionRequester = permissionRequester as? AppKitMicrophonePermissionRequester {
                        return permissionRequester.currentState()
                    }

                    return .notYetRequested
                },
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
                }
            )
        )
        AppComposition.prewarmTranscription()
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarScene(model: sceneModel)
        } label: {
            Image(systemName: sceneModel.statusIcon.systemImageName)
        }
    }
}
