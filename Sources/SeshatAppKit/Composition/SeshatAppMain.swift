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
    @StateObject private var statusItemController: StatusItemControllerHost

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
        _statusItemController = StateObject(
            wrappedValue: StatusItemControllerHost(sceneModel: sceneModel)
        )

        sceneModel.startObserving()
        startupCoordinator.start()
    }

    var body: some Scene {
        // Native NSStatusItem + NSMenu lives in StatusItemController
        // (owned by StatusItemControllerHost above). Per
        // plans/seshat_agent_bundle/03_Surfaces/MenuBarMenu/IMPORTANT.md
        // the menu bar is zero-SwiftUI; we keep a Settings scene here
        // only to satisfy SwiftUI.App's non-empty-body requirement on
        // an LSUIElement app. It never appears.
        Settings {
            EmptyView()
        }
    }
}

/// `@StateObject` host for `StatusItemController`. SwiftUI requires
/// `@StateObject` wrappees to be `ObservableObject`; this wrapper
/// adds the conformance without publishing anything (state flows
/// through `MenuBarSceneModel`, not this host).
@MainActor
final class StatusItemControllerHost: ObservableObject {
    let controller: StatusItemController

    init(sceneModel: MenuBarSceneModel) {
        self.controller = StatusItemController(sceneModel: sceneModel)
    }
}
