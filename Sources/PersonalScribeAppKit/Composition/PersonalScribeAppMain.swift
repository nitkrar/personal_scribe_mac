import AppKit
import ApplicationServices
import Combine
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
        // Bridge SessionCoordinator's `AsyncStream<Float>` audio-level
        // source to the Combine `AnyPublisher<Double, Never>` the pill
        // overlay controller expects. Values are already normalized
        // [0, 1] by the capture pipeline and widen to Double without
        // loss. The forwarding Task lives for the process's lifetime —
        // the coordinator's stream stays open across start/stop cycles.
        let audioLevelSubject = PassthroughSubject<Double, Never>()
        Task { @MainActor [coordinator] in
            let stream = await coordinator.audioLevelStream()
            for await level in stream {
                audioLevelSubject.send(Double(level))
            }
        }
        let pillController = PillOverlayController(
            appStore: appStore,
            audioLevelPublisher: audioLevelSubject.eraseToAnyPublisher(),
            defaults: defaults,
            onTap: {
                Task { await coordinator.toggle() }
            },
            panelBuilder: overlayPanelBuilder
        )
        clipboardOnlyNotice = {
            pillController.showClipboardOnlyNotice()
        }
        let metricsReader: any MetricsReading = {
            do {
                return try AppComposition.makeMetricsReader()
            } catch {
                return EmptyMetricsReader()
            }
        }()
        let unifiedTranscriptReader = PersonalScribeAppMain.defaultTranscriptReader()
        let appKitActiveModeProvider = AppComposition.activeModeProvider
        let unifiedWindowControllerHost = UnifiedWindowControllerHost(
            controllerFactory: {
                UnifiedWindowController(
                    defaults: defaults,
                    transcriptReader: unifiedTranscriptReader,
                    metricsReader: metricsReader,
                    permissionService: appPermissionService,
                    modes: ModeRegistry.all,
                    activeModeProvider: { appKitActiveModeProvider.currentActiveMode() }
                )
            }
        )
        let showUnifiedWindow: @MainActor () -> Void = {
            unifiedWindowControllerHost.showWindow(nil)
        }
        let pasteLastTranscriptAction = PasteLastTranscriptAction(
            transcriptReader: unifiedTranscriptReader,
            outputService: resolvedOutputService
        )
        let statusItemControllerHost = StatusItemControllerHost(
            sceneModel: sceneModel,
            appStore: appStore,
            openHome: showUnifiedWindow,
            openPasteLastTranscript: {
                Task { await pasteLastTranscriptAction.perform() }
            },
            isOnboardingCompleteProvider: isOnboardingCompleteProvider
        )
        _sceneModel = StateObject(wrappedValue: sceneModel)
        _pillController = StateObject(
            wrappedValue: pillController
        )
        _statusItemController = StateObject(
            wrappedValue: statusItemControllerHost
        )
        _unifiedWindowController = StateObject(
            wrappedValue: unifiedWindowControllerHost
        )

        sceneModel.startObserving()

        // First-launch onboarding routing: if permissions haven't been
        // granted yet, auto-open the unified window to the Settings tab
        // so the Permissions sub-tab is one click away. Replaces the
        // pre-M4 OnboardingWindowController auto-open.
        if !isOnboardingCompleteProvider() {
            Task { @MainActor in
                unifiedWindowControllerHost.showWindow(selecting: .settings)
            }
        }
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
        openPasteLastTranscript: @escaping @MainActor () -> Void = {},
        openCheckForUpdates: @escaping @MainActor () -> Void = {},
        isOnboardingCompleteProvider: @escaping @MainActor () -> Bool = {
            PersonalScribeAppMain.onboardingCompletionPreference(defaults: .standard).resolve()
        }
    ) {
        self.controller = StatusItemController(
            sceneModel: sceneModel,
            appStore: appStore,
            openHome: openHome,
            openPasteLastTranscript: openPasteLastTranscript,
            openCheckForUpdates: openCheckForUpdates,
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

/// Fallback MetricsReading used when the SQLite metrics store can't be
/// constructed (e.g. fresh install with no recordings directory yet).
/// Returns zero-rollups + empty recents so the Home tab renders blank
/// instead of crashing.
private struct EmptyMetricsReader: MetricsReading {
    func loadSnapshot(window: MetricsWindow, recentLimit: Int) async throws -> MetricsSnapshot {
        MetricsSnapshot(
            rollups: MetricsRollups.empty(window: window),
            recentTranscriptions: [],
            lastUpdatedAt: Date(),
            lastRefreshReason: .initialLoad
        )
    }

    func recentTranscriptions(limit: Int) async throws -> [TranscriptEntry] {
        []
    }
}
