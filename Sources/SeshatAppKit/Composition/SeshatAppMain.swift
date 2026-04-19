import AppKit
import ApplicationServices
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
    @StateObject private var onboardingController: OnboardingWindowControllerHost
    @StateObject private var settingsWindowController: SettingsWindowControllerHost

    init() {
        self.init(
            coordinator: AppComposition.sessionCoordinator,
            permissionRequester: AppComposition.makeMicrophonePermissionRequester(),
            clipboardWriter: SeshatAppMain.defaultClipboardWriter,
            pasteInjector: PasteInjector(),
            openSettings: SeshatAppMain.defaultOpenSettings,
            overlayPanelBuilder: AppKitPillOverlayPanelBuilder(),
            defaults: .standard,
            inputMonitoringProbe: IOHIDPermissionProbe(),
            isAccessibilityTrusted: { AXIsProcessTrusted() },
            startupCoordinator: nil
        )
    }

    init(
        coordinator: SessionCoordinator,
        permissionRequester: any MicrophonePermissionRequesting,
        clipboardWriter: @escaping @MainActor (String) -> Void = SeshatAppMain.defaultClipboardWriter,
        pasteInjector: any PasteInjecting = PasteInjector(),
        openSettings: @escaping @MainActor () -> Void = SeshatAppMain.defaultOpenSettings,
        overlayPanelBuilder: any PillOverlayPanelBuilding = AppKitPillOverlayPanelBuilder(),
        defaults: UserDefaults = .standard,
        inputMonitoringProbe: any PermissionProbing = IOHIDPermissionProbe(),
        isAccessibilityTrusted: @escaping @MainActor () -> Bool = { AXIsProcessTrusted() },
        startupCoordinator: AppStartupCoordinator? = nil
    ) {
        let startupCoordinator = startupCoordinator
            ?? AppComposition.makeStartupCoordinator(coordinator: coordinator)
        var clipboardOnlyNotice: (@MainActor () -> Void)?
        let microphoneStateProvider: @MainActor () -> MicrophonePermissionState = {
            if let permissionRequester = permissionRequester as? AppKitMicrophonePermissionRequester {
                return permissionRequester.currentState()
            }

            return .notYetRequested
        }
        let onboardingControllerHost = OnboardingWindowControllerHost(
            defaults: defaults,
            startupCoordinator: startupCoordinator,
            microphoneStateProvider: microphoneStateProvider,
            inputMonitoringProbe: inputMonitoringProbe,
            isAccessibilityTrusted: isAccessibilityTrusted
        )
        let isOnboardingCompleteProvider: @MainActor () -> Bool = {
            SeshatOnboardingCompleted.resolve(from: defaults).rawValue
        }

        self.coordinator = coordinator
        self.permissionRequester = permissionRequester
        self.startupCoordinator = startupCoordinator
        let sceneModel = MenuBarSceneModel(
            coordinator: coordinator,
            permissionRequester: permissionRequester,
            permissionStateProvider: microphoneStateProvider,
            clipboardWriter: clipboardWriter,
            pasteInjector: { text in
                pasteInjector.paste(text)
            },
            openSettings: openSettings,
            areCriticalPermissionsGranted: {
                onboardingControllerHost.areCriticalPermissionsGranted
            },
            openOnboardingRequested: {
                onboardingControllerHost.presentPermissionsFallback()
            },
            onClipboardOnlyCopy: {
                clipboardOnlyNotice?()
            }
        )
        let pillController = PillOverlayController(
            statePublisher: sceneModel.$state.eraseToAnyPublisher(),
            preparationProgressPublisher: sceneModel.$preparationProgress.eraseToAnyPublisher(),
            audioLevelPublisher: nil,
            visibilityMode: PillVisibilityMode.resolve(),
            onTap: {
                guard onboardingControllerHost.requestInteractionAccess() else {
                    return
                }

                Task { await coordinator.toggle() }
            },
            panelBuilder: overlayPanelBuilder
        )
        clipboardOnlyNotice = {
            pillController.showClipboardOnlyNotice()
        }
        var showSettingsWindow: @MainActor () -> Void = {}
        let statusItemControllerHost = StatusItemControllerHost(
            sceneModel: sceneModel,
            openSettings: {
                showSettingsWindow()
            },
            isOnboardingCompleteProvider: isOnboardingCompleteProvider
        )
        let settingsWindowControllerHost = SettingsWindowControllerHost(
            controllerFactory: {
                SettingsWindowController(
                    defaults: defaults,
                    menuBarVisibilityProvider: {
                        statusItemControllerHost.isMenuBarVisible
                    },
                    menuBarVisibilitySetter: { isVisible in
                        statusItemControllerHost.setMenuBarVisible(isVisible)
                    }
                )
            }
        )
        showSettingsWindow = {
            settingsWindowControllerHost.showWindow(nil)
        }
        _sceneModel = StateObject(wrappedValue: sceneModel)
        _pillController = StateObject(
            wrappedValue: pillController
        )
        _statusItemController = StateObject(
            wrappedValue: statusItemControllerHost
        )
        _onboardingController = StateObject(
            wrappedValue: onboardingControllerHost
        )
        _settingsWindowController = StateObject(
            wrappedValue: settingsWindowControllerHost
        )

        sceneModel.startObserving()
        onboardingControllerHost.start()
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

private extension SeshatAppMain {
    static let defaultClipboardWriter: @MainActor (String) -> Void = { text in
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    static let defaultOpenSettings: @MainActor () -> Void = {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
        ) else {
            return
        }

        NSWorkspace.shared.open(url)
    }
}

/// `@StateObject` host for `StatusItemController`. SwiftUI requires
/// `@StateObject` wrappees to be `ObservableObject`; this wrapper
/// adds the conformance without publishing anything (state flows
/// through `MenuBarSceneModel`, not this host).
@MainActor
final class StatusItemControllerHost: ObservableObject {
    let controller: StatusItemController

    init(
        sceneModel: MenuBarSceneModel,
        openSettings: @escaping @MainActor () -> Void = {},
        isOnboardingCompleteProvider: @escaping @MainActor () -> Bool = {
            SeshatOnboardingCompleted.resolve().rawValue
        }
    ) {
        self.controller = StatusItemController(
            sceneModel: sceneModel,
            openSettings: openSettings,
            isOnboardingCompleteProvider: isOnboardingCompleteProvider
        )
    }

    var isMenuBarVisible: Bool {
        controller.isStatusItemVisible
    }

    func setMenuBarVisible(_ isVisible: Bool) {
        controller.setStatusItemVisible(isVisible)
    }
}
