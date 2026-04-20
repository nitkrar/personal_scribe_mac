import AppKit
import ApplicationServices
import SwiftUI
import PersonalScribeCore
import PersonalScribeSession

@main
@MainActor
struct PersonalScribeAppMain: App {
    let coordinator: SessionCoordinator
    let startupCoordinator: AppStartupCoordinator

    @StateObject private var sceneModel: MenuBarSceneModel
    @StateObject private var pillController: PillOverlayController
    @StateObject private var statusItemController: StatusItemControllerHost
    @StateObject private var onboardingController: OnboardingWindowControllerHost
    @StateObject private var notesWindowController: NotesWindowControllerHost
    @StateObject private var settingsWindowController: SettingsWindowControllerHost
    @StateObject private var unifiedWindowController: UnifiedWindowControllerHost

    init() {
        self.init(
            coordinator: AppComposition.sessionCoordinator,
            permissionService: AppComposition.makePermissionService(),
            clipboardWriter: PersonalScribeAppMain.defaultClipboardWriter,
            openSettings: PersonalScribeAppMain.defaultOpenSettings,
            overlayPanelBuilder: AppKitPillOverlayPanelBuilder(),
            defaults: .standard,
            startupCoordinator: nil
        )
    }

    init(
        coordinator: SessionCoordinator,
        permissionService: (any PermissionService)? = nil,
        clipboardWriter: @escaping @MainActor (String) -> Void = PersonalScribeAppMain.defaultClipboardWriter,
        outputService: (any OutputService)? = nil,
        openSettings: @escaping @MainActor () -> Void = PersonalScribeAppMain.defaultOpenSettings,
        overlayPanelBuilder: any PillOverlayPanelBuilding = AppKitPillOverlayPanelBuilder(),
        defaults: UserDefaults = .standard,
        isAccessibilityTrusted: @escaping @MainActor () -> Bool = { AXIsProcessTrusted() },
        notesWindowControllerFactory: @escaping @MainActor () -> NotesWindowController = {
            NotesWindowController(transcriptReader: PersonalScribeAppMain.defaultTranscriptReader())
        },
        startupCoordinator: AppStartupCoordinator? = nil
    ) {
        // Run the one-shot UserDefaults rename migration before any preference
        // read. Idempotent; bounded by PreferenceMigrator.currentMigrationVersion.
        PreferenceMigrator.migrate(defaults: defaults)

        let resolvedPermissionService = permissionService ?? AppComposition.makePermissionService()
        let appPermissionService = Self.makePermissionServiceAdapter(wrapping: resolvedPermissionService)
        let appStore = AppStore(
            session: coordinator.appStoreSessionProvider(),
            permissions: appPermissionService,
            activeModeSource: AppComposition.activeModeProvider,
            visibilityModeSource: AppKitVisibilityModeProvider(defaults: defaults)
        )
        appStore.start()
        let resolvedOutputService = outputService
            ?? ClipboardBatchOutput(
                defaults: defaults,
                isAccessibilityTrusted: isAccessibilityTrusted
            )
        let startupCoordinator = startupCoordinator
            ?? AppComposition.makeStartupCoordinator(
                coordinator: coordinator,
                hotkeyMonitor: AppComposition.makeGlobalHotkeyMonitor(
                    permissionService: appPermissionService,
                    coordinator: coordinator
                )
            )
        var clipboardOnlyNotice: (@MainActor () -> Void)?
        let onboardingControllerHost = OnboardingWindowControllerHost(
            defaults: defaults,
            startupCoordinator: startupCoordinator,
            permissionService: appPermissionService
        )
        let onboardingCompletionPreference = Self.onboardingCompletionPreference(defaults: defaults)
        let isOnboardingCompleteProvider: @MainActor () -> Bool = {
            onboardingCompletionPreference.resolve()
        }

        self.coordinator = coordinator
        self.startupCoordinator = startupCoordinator
        let sceneModel = MenuBarSceneModel(
            appStore: appStore,
            coordinator: coordinator,
            clipboardWriter: clipboardWriter,
            outputService: resolvedOutputService,
            permissionService: appPermissionService,
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
        let unifiedWindowControllerHost = UnifiedWindowControllerHost(
            controllerFactory: {
                UnifiedWindowController(defaults: defaults)
            }
        )
        var showNotesWindow: @MainActor () -> Void = {}
        var showSettingsWindow: @MainActor () -> Void = {}
        let showUnifiedWindow: @MainActor () -> Void = {
            unifiedWindowControllerHost.showWindow(nil)
        }
        let statusItemControllerHost = StatusItemControllerHost(
            sceneModel: sceneModel,
            appStore: appStore,
            openHome: showUnifiedWindow,
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
        _unifiedWindowController = StateObject(
            wrappedValue: unifiedWindowControllerHost
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

extension PersonalScribeAppMain {
    fileprivate static func onboardingCompletionPreference(defaults: UserDefaults) -> Preference<Bool> {
        Preference(
            key: "OnboardingCompleted",
            default: false,
            defaults: defaults
        )
    }

    static func defaultTranscriptReader(
        logger: PersonalScribeLogger = PersonalScribeLogger(category: PersonalScribeLogCategory.ui)
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

    private static func makePermissionServiceAdapter(
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
        openHome: @escaping @MainActor () -> Void = {},
        openHistory: @escaping @MainActor () -> Void = {},
        openSettings: @escaping @MainActor () -> Void = {},
        isOnboardingCompleteProvider: @escaping @MainActor () -> Bool = {
            PersonalScribeAppMain.onboardingCompletionPreference(defaults: .standard).resolve()
        }
    ) {
        self.controller = StatusItemController(
            sceneModel: sceneModel,
            appStore: appStore,
            openHome: openHome,
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
