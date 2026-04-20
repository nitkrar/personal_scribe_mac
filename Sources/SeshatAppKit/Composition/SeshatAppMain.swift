import AppKit
import ApplicationServices
import SwiftUI
import SeshatCore
import SeshatSession

@main
@MainActor
struct SeshatAppMain: App {
    let coordinator: SessionCoordinator
    let startupCoordinator: AppStartupCoordinator

    @StateObject private var sceneModel: MenuBarSceneModel
    @StateObject private var pillController: PillOverlayController
    @StateObject private var statusItemController: StatusItemControllerHost
    @StateObject private var onboardingController: OnboardingWindowControllerHost
    @StateObject private var notesWindowController: NotesWindowControllerHost
    @StateObject private var settingsWindowController: SettingsWindowControllerHost

    init() {
        let permissionService: any PermissionService = AppComposition.makePermissionService()
        self.init(
            coordinator: AppComposition.sessionCoordinator,
            permissionRequester: AppComposition.makeMicrophonePermissionRequester(),
            permissionService: permissionService,
            clipboardWriter: SeshatAppMain.defaultClipboardWriter,
            openSettings: SeshatAppMain.defaultOpenSettings,
            overlayPanelBuilder: AppKitPillOverlayPanelBuilder(),
            defaults: .standard,
            inputMonitoringProbe: IOHIDPermissionProbe(),
            startupCoordinator: nil
        )
    }

    init(
        coordinator: SessionCoordinator,
        permissionRequester: any MicrophonePermissionRequesting,
        permissionService: (any PermissionService)? = nil,
        clipboardWriter: @escaping @MainActor (String) -> Void = SeshatAppMain.defaultClipboardWriter,
        pasteInjector: (any PasteInjecting)? = nil,
        openSettings: @escaping @MainActor () -> Void = SeshatAppMain.defaultOpenSettings,
        overlayPanelBuilder: any PillOverlayPanelBuilding = AppKitPillOverlayPanelBuilder(),
        defaults: UserDefaults = .standard,
        inputMonitoringProbe: any PermissionProbing = IOHIDPermissionProbe(),
        isAccessibilityTrusted: @escaping @MainActor () -> Bool = { AXIsProcessTrusted() },
        notesWindowControllerFactory: @escaping @MainActor () -> NotesWindowController = {
            NotesWindowController(transcriptReader: SeshatAppMain.defaultTranscriptReader())
        },
        startupCoordinator: AppStartupCoordinator? = nil
    ) {
        let compatibilityPermissionService: PermissionServiceAdapter =
            if let permissionService {
                Self.makeCompatibilityPermissionServiceAdapter(wrapping: permissionService)
            } else {
                Self.makeCompatibilityPermissionService(
                    permissionRequester: permissionRequester,
                    inputMonitoringProbe: inputMonitoringProbe,
                    isAccessibilityTrusted: isAccessibilityTrusted
                )
            }
        let appStore = AppStore(
            session: coordinator.appStoreSessionProvider(),
            permissions: compatibilityPermissionService,
            activeModeSource: AppKitActiveModeProvider(),
            visibilityModeSource: AppKitVisibilityModeProvider(defaults: defaults)
        )
        appStore.start()
        let resolvedOutputService: any OutputService = ClipboardBatchOutput()
        let startupCoordinator = startupCoordinator
            ?? AppComposition.makeStartupCoordinator(
                coordinator: coordinator,
                hotkeyMonitor: AppComposition.makeGlobalHotkeyMonitor(
                    permissionService: compatibilityPermissionService,
                    coordinator: coordinator
                )
            )
        var clipboardOnlyNotice: (@MainActor () -> Void)?
        let onboardingControllerHost = OnboardingWindowControllerHost(
            defaults: defaults,
            startupCoordinator: startupCoordinator,
            permissionService: compatibilityPermissionService,
            microphoneStateProvider: { .notYetRequested },
            inputMonitoringProbe: inputMonitoringProbe,
            isAccessibilityTrusted: isAccessibilityTrusted
        )
        let isOnboardingCompleteProvider: @MainActor () -> Bool = {
            SeshatOnboardingCompleted.resolve(from: defaults).rawValue
        }

        self.coordinator = coordinator
        self.startupCoordinator = startupCoordinator
        let sceneModel = MenuBarSceneModel(
            appStore: appStore,
            coordinator: coordinator,
            clipboardWriter: clipboardWriter,
            outputService: resolvedOutputService,
            permissionService: compatibilityPermissionService,
            openURL: { url in
                _ = NSWorkspace.shared.open(url)
            },
            onClipboardOnlyCopy: {
                clipboardOnlyNotice?()
            }
        )
        let pillController = PillOverlayController(
            appStore: appStore,
            audioLevelPublisher: nil,
            defaults: defaults,
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
        let notesWindowControllerHost = NotesWindowControllerHost(
            controllerFactory: notesWindowControllerFactory
        )
        var showNotesWindow: @MainActor () -> Void = {}
        var showSettingsWindow: @MainActor () -> Void = {}
        let statusItemControllerHost = StatusItemControllerHost(
            sceneModel: sceneModel,
            appStore: appStore,
            openHistory: {
                showNotesWindow()
            },
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
            settingsWindowControllerHost.showWindow(nil as Any?)
        }
        showNotesWindow = {
            guard isOnboardingCompleteProvider() else {
                return
            }

            notesWindowControllerHost.showWindow(nil)
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
        _notesWindowController = StateObject(
            wrappedValue: notesWindowControllerHost
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

extension SeshatAppMain {
    static func defaultTranscriptReader(
        logger: SeshatLogger = SeshatLogger(category: SeshatLogCategory.ui)
    ) -> any TranscriptReading {
        do {
            let storageLocator = AppConfig.liveStorageLocator()
            let store = try SQLiteTranscriptStore(storageLocator: storageLocator)
            return SQLiteTranscriptReader(store: store)
        } catch {
            logger.error("NotesWindow transcript reader init failed; falling back to empty history", error: error)
            return EmptyTranscriptReader()
        }
    }

    static let defaultClipboardWriter: @MainActor (String) -> Void = { text in
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    static let defaultOpenSettings: @MainActor () -> Void = {
        NSWorkspace.shared.open(
            PermissionServiceAdapter.defaultSystemSettingsDeepLink(for: .microphone)
        )
    }

    static func makeCompatibilityPermissionService(
        permissionRequester: any MicrophonePermissionRequesting,
        inputMonitoringProbe: any PermissionProbing,
        isAccessibilityTrusted: @escaping @MainActor () -> Bool
    ) -> PermissionServiceAdapter {
        @MainActor
        final class StateBox {
            var statuses: [Permission: PermissionStatus]

            init(statuses: [Permission: PermissionStatus]) {
                self.statuses = statuses
            }
        }

        let initialMicrophoneStatus: PermissionStatus
        if let permissionRequester = permissionRequester as? AppKitMicrophonePermissionRequester {
            initialMicrophoneStatus = permissionRequester.currentState().unifiedPermissionStatus
        } else {
            initialMicrophoneStatus = .pending
        }

        let box = StateBox(statuses: [
            .microphone: initialMicrophoneStatus,
            .inputMonitoring: inputMonitoringProbe.checkInputMonitoring().unifiedPermissionStatus,
            .accessibility: isAccessibilityTrusted() ? .granted : .pending,
        ])

        return PermissionServiceAdapter(
            initialStatuses: box.statuses,
            statusReader: { permission in
                switch permission {
                case .inputMonitoring:
                    let status = inputMonitoringProbe.checkInputMonitoring().unifiedPermissionStatus
                    box.statuses[.inputMonitoring] = status
                    return status
                case .accessibility:
                    let status: PermissionStatus = isAccessibilityTrusted() ? .granted : .pending
                    box.statuses[.accessibility] = status
                    return status
                case .microphone:
                    return box.statuses[.microphone] ?? .pending
                }
            },
            requester: { permission in
                switch permission {
                case .microphone:
                    let granted = await permissionRequester.requestAccess()
                    let finalStatus: PermissionStatus = granted ? .granted : .denied
                    box.statuses[.microphone] = finalStatus
                    return RequestOutcome(
                        prompted: true,
                        openedSettings: false,
                        requiresRelaunch: false,
                        finalStatus: finalStatus
                    )
                case .inputMonitoring:
                    let finalStatus = inputMonitoringProbe.checkInputMonitoring().unifiedPermissionStatus
                    box.statuses[.inputMonitoring] = finalStatus
                    return RequestOutcome(
                        prompted: false,
                        openedSettings: false,
                        requiresRelaunch: true,
                        finalStatus: finalStatus
                    )
                case .accessibility:
                    let finalStatus: PermissionStatus = isAccessibilityTrusted() ? .granted : .pending
                    box.statuses[.accessibility] = finalStatus
                    return RequestOutcome(
                        prompted: false,
                        openedSettings: false,
                        requiresRelaunch: false,
                        finalStatus: finalStatus
                    )
                }
            },
            refresher: {
                box.statuses[.inputMonitoring] = inputMonitoringProbe.checkInputMonitoring().unifiedPermissionStatus
                box.statuses[.accessibility] = isAccessibilityTrusted() ? .granted : .pending
                return box.statuses
            }
        )
    }

    private static func makeCompatibilityPermissionServiceAdapter(
        wrapping permissionService: any PermissionService
    ) -> PermissionServiceAdapter {
        if let permissionService = permissionService as? PermissionServiceAdapter {
            return permissionService
        }

        return wrapPermissionService(permissionService)
    }

    private static func wrapPermissionService<Service: PermissionService>(
        _ permissionService: Service
    ) -> PermissionServiceAdapter {
        PermissionServiceAdapter(wrapping: permissionService)
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
        appStore: AppStore,
        openHistory: @escaping @MainActor () -> Void = {},
        openSettings: @escaping @MainActor () -> Void = {},
        isOnboardingCompleteProvider: @escaping @MainActor () -> Bool = {
            SeshatOnboardingCompleted.resolve().rawValue
        }
    ) {
        self.controller = StatusItemController(
            sceneModel: sceneModel,
            appStore: appStore,
            openHistory: openHistory,
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

private struct EmptyTranscriptReader: TranscriptReading {
    func recent(limit: Int) async -> [TranscriptEntry] {
        []
    }

    func search(query: String) async -> [TranscriptEntry] {
        []
    }

    func all() async -> [TranscriptEntry] {
        []
    }
}
