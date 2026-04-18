import AppKit
import SwiftUI
import SeshatCore
import SeshatSession

@main
@MainActor
struct SeshatAppMain: App {
    let coordinator: SessionCoordinator
    let permissionRequester: any MicrophonePermissionRequesting
    let startupCoordinator: AppStartupCoordinator

    @StateObject private var sceneModel: MenuBarSceneModel
    @StateObject private var pillController: PillOverlayController

    init() {
        self.init(
            coordinator: AppComposition.sessionCoordinator,
            permissionRequester: AppComposition.makeMicrophonePermissionRequester(),
            pasteInjector: PasteInjector(),
            startupCoordinator: nil
        )
    }

    init(
        coordinator: SessionCoordinator,
        permissionRequester: any MicrophonePermissionRequesting,
        pasteInjector: PasteInjector = PasteInjector(),
        startupCoordinator: AppStartupCoordinator? = nil
    ) {
        let startupCoordinator = startupCoordinator
            ?? AppComposition.makeStartupCoordinator(coordinator: coordinator)

        self.coordinator = coordinator
        self.permissionRequester = permissionRequester
        self.startupCoordinator = startupCoordinator
        let sceneModel = MenuBarSceneModel(
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
            pasteInjector: { text in
                pasteInjector.paste(text)
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
        _sceneModel = StateObject(wrappedValue: sceneModel)
        _pillController = StateObject(
            wrappedValue: PillOverlayController(
                statePublisher: sceneModel.$state.eraseToAnyPublisher(),
                preparationProgressPublisher: sceneModel.$preparationProgress.eraseToAnyPublisher(),
                onTap: {
                    Task { await coordinator.toggle() }
                }
            )
        )

        sceneModel.startObserving()
        Task { @MainActor [startupCoordinator] in
            // Let SwiftUI install the status item before background startup work begins.
            await Task.yield()
            startupCoordinator.start()
        }
    }

    var body: some Scene {
        // Default .menu style — popover renders as AppKit NSMenu. Keep the
        // popover content simple (Text + Button only); ProgressView / nested
        // VStacks don't render in NSMenu and caused silent click-breakage.
        // Rich UI (download progress, recording pulse) lives in the pill overlay.
        MenuBarExtra {
            MenuBarScene(model: sceneModel)
        } label: {
            Image(systemName: sceneModel.statusIcon.systemImageName)
                .accessibilityLabel(sceneModel.statusIcon.accessibilityLabel)
        }
    }
}
