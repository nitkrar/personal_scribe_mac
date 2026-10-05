import AppKit
import ApplicationServices
import Combine
import SwiftUI
import PersonalScribeAudio
import PersonalScribeCore
import PersonalScribeSession

@main
@MainActor
struct PersonalScribeAppMain: App {
    let coordinator: SessionCoordinator
    let startupCoordinator: AppStartupCoordinator
    let onboardingCompletionObserver: OnboardingCompletionObserver

    @NSApplicationDelegateAdaptor(FastExitApplicationTerminationDelegate.self)
    private var applicationTerminationDelegate
    @StateObject private var sceneModel: MenuBarSceneModel
    @StateObject private var pillController: PillOverlayController
    @StateObject private var statusItemController: StatusItemControllerHost
    @StateObject private var unifiedWindowController: UnifiedWindowControllerHost
    @StateObject private var escapeKeyMonitorHost: EscapeKeyMonitorHost
    @StateObject private var diagnosticsOverlayController: LiveDiagnosticsOverlayController

    init() {
        // Before any composition work: a second copy must not touch
        // shared state (DB, models, hotkey tap) at all.
        SingleInstanceGuard.exitIfAnotherInstanceIsRunning()
        let defaults = UserDefaults.standard
        // Run preference migrations before any AppComposition access so
        // shared singletons resolve upgraded defaults on first launch
        // after a migration lands.
        PreferenceMigrator.migrate(defaults: defaults)
        // Must run before anything opens files under the base directory.
        let storageLogger = AppComposition.makeLogger(PersonalScribeLogCategory.app)
        do {
            try BaseDirectoryMigrator(defaults: defaults, logger: storageLogger).applyPendingMoveIfNeeded()
        } catch {
            storageLogger.error("Storage location move failed; staying on the current location", error: error)
        }
        AppComposition.startDiagnosticsMaintenanceIfNeeded()
        AppComposition.startRecordingRetentionSweeperIfNeeded()
        self.init(
            coordinator: AppComposition.sessionCoordinator,
            permissionService: AppComposition.makePermissionService(),
            clipboardWriter: PersonalScribeAppMain.defaultClipboardWriter,
            openSettings: PersonalScribeAppMain.defaultOpenSettings,
            overlayPanelBuilder: AppKitPillOverlayPanelBuilder(),
            defaults: defaults,
            startupCoordinator: nil
        )
    }

    init(
        coordinator: SessionCoordinator,
        permissionService: (any PermissionService)? = nil,
        clipboardWriter: @escaping @MainActor (String) -> Void = PersonalScribeAppMain.defaultClipboardWriter,
        openSettings: @escaping @MainActor () -> Void = PersonalScribeAppMain.defaultOpenSettings,
        overlayPanelBuilder: any PillOverlayPanelBuilding = AppKitPillOverlayPanelBuilder(),
        defaults: UserDefaults = .standard,
        startupCoordinator: AppStartupCoordinator? = nil,
        showWindowAtLaunch: Bool = true
    ) {
        // Run the one-shot UserDefaults rename migration before any preference
        // read. Idempotent; bounded by PreferenceMigrator.currentMigrationVersion.
        PreferenceMigrator.migrate(defaults: defaults)

        let resolvedPermissionService = permissionService ?? AppComposition.makePermissionService()
        let appPermissionService = Self.makePermissionServiceAdapter(wrapping: resolvedPermissionService)
        let appStore = AppStore(
            session: coordinator.appStoreSessionProvider(),
            permissions: appPermissionService,
            workflowModeRegistry: AppComposition.workflowModeRegistry,
            visibilityModeSource: AppKitVisibilityModeProvider(defaults: defaults)
        )
        appStore.start()
        let isOnboardingCompleteProvider: @MainActor () -> Bool = {
            OnboardingState.resolve(from: defaults) == .completed
        }
        let selectableModesProvider: @MainActor () -> [WorkflowMode] = {
            AppComposition.currentlyValidCustomModes(
                among: AppComposition.workflowModeRegistry.customModes
            )
        }

        self.coordinator = coordinator
        let sceneModel = MenuBarSceneModel(
            appStore: appStore,
            coordinator: coordinator,
            clipboardWriter: clipboardWriter,
            permissionService: appPermissionService,
            openURL: { url in
                _ = NSWorkspace.shared.open(url)
            },
            logger: AppComposition.makeLogger(PersonalScribeLogCategory.ui)
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
            toastPublisher: AppComposition.toastBroadcaster.publisher,
            defaults: defaults,
            onTap: {
                Task { await coordinator.toggle() }
            },
            panelBuilder: overlayPanelBuilder,
            openVadSettingsAction: nil
        )
        Task {
            await coordinator.setPausedAutoFinalizeHandler {
                await MainActor.run {
                    AppComposition.toastBroadcaster.post(
                        .success("Saved to History")
                    )
                }
            }
        }
        pillController.configureModeMenu(
            modesProvider: selectableModesProvider,
            modeUpdates: AppComposition.workflowModeRegistry.customModesStream(),
            modeAvailabilityUpdates: AppComposition.modelService.$activeModelIDs
                .map { _ in () }
                .merge(with: AppComposition.modelService.$downloadStates.map { _ in () })
                .dropFirst(2)
                .eraseToAnyPublisher(),
            currentModeIDProvider: {
                AppComposition.workflowModeRegistry.currentMode.id
            },
            onSelect: { mode in
                await AppComposition.selectModeIfNeeded(
                    selectedModeID: mode.id,
                    currentModeID: AppComposition.workflowModeRegistry.currentMode.id,
                    finalizePaused: { await coordinator.finalizePausedForExternalInterruption() },
                    setCurrent: { AppComposition.workflowModeRegistry.setCurrent(id: $0) }
                )
            }
        )
        // Final delivery runs in the pipeline's output stage; it raises
        // the clipboard-only notice when paste fell back to clipboard.
        AppComposition.sessionOutputStage.onClipboardOnlyCopy = { notice in
            pillController.showClipboardOnlyNotice(notice)
        }
        pillController.viewModel.onPause = { [weak coordinator] in
            Task { await coordinator?.pauseIfRecording() }
        }
        pillController.viewModel.onResume = { [weak coordinator] in
            Task { await coordinator?.resumeIfPaused() }
        }
        pillController.viewModel.onStop = { [weak coordinator] in
            Task { await coordinator?.stopIfActive() }
        }

        let diagnosticsOverlayController = LiveDiagnosticsOverlayController(
            store: AppComposition.diagnosticsStore
        )

        // Esc cancels only an active recording.
        let escapeKeyMonitor = EscapeKeyMonitor(
            router: AppComposition.keyEventRouter
        ) { [weak pillController, weak coordinator] in
            guard let pillController else { return false }
            let visibility = pillController.viewModel.visibility
            switch visibility {
            case .holdToRecord, .recording, .paused:
                break
            case .hidden, .idle, .downloading, .loading, .transcribing,
                 .cancelled, .error:
                return false
            }
            Task { [weak coordinator] in
                await coordinator?.cancelIfActive()
            }
            return true
        }

        pillController.viewModel.onResumeCancelledRecording = { [weak coordinator] in
            Task { await coordinator?.resumeCancelled() }
        }

        // #071: hold-start now routes through `coordinator.startHoldIfIdle()`
        // which publishes `.holdRecording` eagerly to the pipeline.
        // `AppStore.derivePillVisibility` maps that to `.holdToRecord`
        // for the pill overlay — no side-channel push needed.
        let startupCoordinator = startupCoordinator
            ?? AppComposition.makeStartupCoordinator(
                coordinator: coordinator,
                hotkeyMonitor: AppComposition.makeGlobalHotkeyMonitor(coordinator: coordinator)
            )
        self.startupCoordinator = startupCoordinator
        let metricsReader: any MetricsReading = {
            guard let appDatabase = AppComposition.appDatabase else {
                return EmptyMetricsReader()
            }
            return SQLiteMetricsService(
                appDatabase: appDatabase,
                logger: AppComposition.makeLogger(PersonalScribeLogCategory.app),
                referenceDateProvider: Date.init
            )
        }()
        let metricsStore = MetricsSnapshotStore(
            reader: metricsReader,
            logger: AppComposition.makeLogger(PersonalScribeLogCategory.app)
        )
        metricsStore.startObserving()
        let unifiedTranscriptReader = PersonalScribeAppMain.defaultTranscriptReader(
            logger: AppComposition.makeLogger(PersonalScribeLogCategory.ui)
        )
        let modelService = AppComposition.modelService
        // Shared input-device provider — one `AVFoundationInputDeviceProvider`
        // instance backs both the menu-bar Microphone submenu AND the
        // unified-window sidebar footer readout (#008). The provider is
        // stateless (reads from AVFoundation + UserDefaults on each pull)
        // so sharing is safe and keeps both surfaces in sync.
        let inputDeviceProvider: any AudioInputDeviceProviding =
            AVFoundationInputDeviceProvider(defaults: defaults)
        let offlineRetranscriptionAction = AppComposition.offlineTranscriptionCoordinator.map { coordinator in
            OfflineRetranscriptionAction(
                transcriptReader: unifiedTranscriptReader,
                coordinator: coordinator,
                toastBroadcaster: AppComposition.toastBroadcaster,
                clipboardWriter: clipboardWriter
            )
        }
        // Forward-declared reference so the UnifiedWindowController's
        // factory closure can read `statusItemControllerHost` after
        // the latter is constructed below. Captured-by-reference via
        // the `var` binding — closure invocations (lazy, on first
        // window show) see the value set after init completes.
        var statusItemHostRef: StatusItemControllerHost?
        let unifiedWindowControllerHost = UnifiedWindowControllerHost(
            controllerFactory: {
                UnifiedWindowController(
                    defaults: defaults,
                    transcriptReader: unifiedTranscriptReader,
                    metricsStore: metricsStore,
                    permissionService: appPermissionService,
                    inputDeviceProvider: inputDeviceProvider,
                    modes: WorkflowModeRegistry.builtInModes,
                    modelService: modelService,
                    offlineTranscriptionCoordinator: AppComposition.offlineTranscriptionCoordinator,
                    offlineRetranscriptionAction: offlineRetranscriptionAction,
                    setActiveMode: { mode in
                        // #089: menu-bar / pill switcher set the runtime
                        // *current* mode, not the persisted default.
                        // RecipeBuilder resolves descriptors per Kind via
                        // ActiveModelService at session start.
                        await AppComposition.selectModeIfNeeded(
                            selectedModeID: mode.id,
                            currentModeID: AppComposition.workflowModeRegistry.currentMode.id,
                            finalizePaused: { await coordinator.finalizePausedForExternalInterruption() },
                            setCurrent: { AppComposition.workflowModeRegistry.setCurrent(id: $0) }
                        )
                    },
                    menuBarVisibilityProvider: {
                        statusItemHostRef?.isMenuBarVisible ?? true
                    },
                    menuBarVisibilitySetter: { isVisible in
                        statusItemHostRef?.setMenuBarVisible(isVisible)
                    },
                    openDiagnosticsWindow: {
                        diagnosticsOverlayController.openWindow()
                    },
                    logger: AppComposition.makeLogger(PersonalScribeLogCategory.ui)
                )
            }
        )
        // Menu-bar "Home" must route to the Home tab, not just raise
        // whatever tab was last active. Using the selecting variant
        // matches the `.settings` paths below (⌘, and onboarding).
        let openHomeTab: @MainActor () -> Void = {
            unifiedWindowControllerHost.showWindow(selecting: .home)
        }
        let openTranscriptionsTab: @MainActor () -> Void = {
            unifiedWindowControllerHost.showWindow(selecting: .transcriptions)
        }
        let openSettingsTab: @MainActor () -> Void = {
            unifiedWindowControllerHost.showWindow(selecting: .settings)
        }
        // #046 Stage B: wire the pill's VAD auto-stopped notification link
        // to the same Settings-open closure. Post-init setter because the
        // pill controller is constructed before `unifiedWindowControllerHost`.
        pillController.setOpenVadSettingsAction(openSettingsTab)
        // Menu-bar "Copy Last Transcript" is strict copy-to-clipboard —
        // no auto-paste, no AX probe. The paste-at-cursor flow is
        // served by the hotkey / pill path where cursor context is
        // preserved. See bug #9 (2026-04-21 dogfood).
        let copyLastTranscriptLogger = AppComposition.makeLogger(PersonalScribeLogCategory.ui)
        let copyLastTranscriptAction = CopyLastTranscriptAction(
            transcriptReader: unifiedTranscriptReader,
            clipboardWriter: CopyLastTranscriptAction.defaultClipboardWriter,
            onCompleted: { outcome in
                // TODO: wire a user-visible toast once a notice surface
                // exists — tracked with the general feedback polish pass.
                switch outcome {
                case .copied(let text):
                    copyLastTranscriptLogger.info("Copy Last Transcript: copied \(text.count) char(s) to clipboard")
                case .emptyHistory:
                    copyLastTranscriptLogger.info("Copy Last Transcript: history is empty — no-op (clipboard unchanged)")
                }
            }
        )
        let prequitHandler = FastExitApplicationTerminationHandler.makePrequitHandler(
            stopIfActive: {
                // Stop an active recording before fast-exit so
                // `SystemAudioMuter` restores the prior output mute state.
                await coordinator.finishForApplicationTermination()
            },
            shutdownPreparedWhisperCppAdapters: {
                await coordinator.shutdownPreparedWhisperCppAdaptersForApplicationTermination()
            }
        )
        let statusItemControllerHost = StatusItemControllerHost(
            sceneModel: sceneModel,
            appStore: appStore,
            openHome: openHomeTab,
            openTranscriptions: openTranscriptionsTab,
            openSettings: openSettingsTab,
            openCopyLastTranscript: {
                Task { await copyLastTranscriptAction.perform() }
            },
            offlineRetranscriptionAction: offlineRetranscriptionAction,
            isOnboardingCompleteProvider: isOnboardingCompleteProvider,
            inputDeviceProvider: inputDeviceProvider,
            modesProvider: {
                selectableModesProvider()
            },
            setActiveMode: { mode in
                // #089: menu-bar submenu picks the runtime *current*
                // mode. Recipe resolution against ActiveModelService
                // happens at session start via RecipeBuilder.
                await AppComposition.selectModeIfNeeded(
                    selectedModeID: mode.id,
                    currentModeID: AppComposition.workflowModeRegistry.currentMode.id,
                    finalizePaused: { await coordinator.finalizePausedForExternalInterruption() },
                    setCurrent: { AppComposition.workflowModeRegistry.setCurrent(id: $0) }
                )
            },
            prequitHandler: prequitHandler
        )
        // Back-wire the menu-bar visibility ref so the unified window's
        // Settings → General "Show menu bar item" toggle actually flips
        // `NSStatusItem.isVisible`. Closures captured the `var` by
        // reference; setting it now means any subsequent unified-window
        // factory call resolves to the live host.
        statusItemHostRef = statusItemControllerHost
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
        _escapeKeyMonitorHost = StateObject(
            wrappedValue: EscapeKeyMonitorHost(
                monitor: escapeKeyMonitor,
                visibility: pillController.viewModel.$visibility.eraseToAnyPublisher()
            )
        )
        _diagnosticsOverlayController = StateObject(
            wrappedValue: diagnosticsOverlayController
        )

        sceneModel.startObserving()
        startupCoordinator.start()

        // Apply the persisted "Background mode" preference. Info.plist no
        // longer carries `LSUIElement: true` — the app launches as
        // `.regular` by default. If the user has opted in to background
        // mode, flip to `.accessory` here. Changes only take effect on
        // relaunch (the Settings toggle does not flip live — see
        // `GeneralTabViewModel.setBackgroundMode`).
        if BackgroundLaunchPreference.resolve(from: defaults) {
            NSApp.setActivationPolicy(.accessory)
        }

        // #015: watch the permission service and flip
        // `OnboardingCompleted` the first time Mic + Accessibility
        // both land as `.granted`. Covers the "perms granted before
        // launch" case (flag flips immediately) AND the "user grants
        // during first session" case (observer fires on publish). Once
        // flipped, the observer self-terminates — later revokes in
        // System Settings don't churn the flag.
        let observer = OnboardingCompletionObserver(
            permissionService: resolvedPermissionService,
            defaults: defaults
        )
        observer.start()
        self.onboardingCompletionObserver = observer

        // Read after `observer.start()`, which may complete onboarding
        // synchronously when permissions are already granted.
        let launchTab = Self.launchTab(isOnboardingComplete: isOnboardingCompleteProvider())
        if showWindowAtLaunch {
            Task { @MainActor in
                unifiedWindowControllerHost.showWindow(selecting: launchTab)
            }
        }

        applicationTerminationDelegate.installPrequitHandler(prequitHandler)
        // Second launch while running: show the main window (Background
        // mode has no Dock icon / window to bring forward otherwise).
        applicationTerminationDelegate.installReopenHandler {
            unifiedWindowControllerHost.showWindow()
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    var body: some Scene {
        // Native NSStatusItem + NSMenu lives in StatusItemController
        // (owned by StatusItemControllerHost above). Per
        // plans/seshat_agent_bundle/03_Surfaces/MenuBarMenu/IMPORTANT.md
        // The menu bar is AppKit-owned. A never-inserted MenuBarExtra
        // satisfies SwiftUI.App's non-empty-body requirement without
        // creating a launch-time window.
        //
        // `.commands { CommandGroup(replacing: .appSettings) }` overrides
        // SwiftUI's default `⌘,` handler so the shortcut opens our real
        // settings surface (the unified window's Settings tab).
        MenuBarExtra(AppBrand.displayName, isInserted: .constant(false)) {
            EmptyView()
        }
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") { [unifiedWindowController] in
                    unifiedWindowController.showWindow(selecting: .settings)
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}

extension PersonalScribeAppMain {
    /// Settings (for permissions) until onboarding completes, then Home.
    static func launchTab(isOnboardingComplete: Bool) -> AppTab {
        isOnboardingComplete ? .home : .settings
    }

    static func defaultTranscriptReader(
        logger: PersonalScribeLogger
    ) -> any TranscriptReading {
        guard let repository = AppComposition.transcriptRepository else {
            logger.error("NotesWindow transcript reader: shared AppDatabase unavailable; falling back to empty history")
            return EmptyTranscriptReader()
        }
        return repository
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
        openTranscriptions: @escaping @MainActor () -> Void = {},
        openSettings: @escaping @MainActor () -> Void = {},
        openCopyLastTranscript: @escaping @MainActor () -> Void = {},
        offlineRetranscriptionAction: OfflineRetranscriptionAction? = nil,
        isOnboardingCompleteProvider: @escaping @MainActor () -> Bool = {
            OnboardingState.resolve() == .completed
        },
        inputDeviceProvider: (any AudioInputDeviceProviding)? = nil,
        modesProvider: @escaping @MainActor () -> [WorkflowMode] = { WorkflowModeRegistry.builtInModes },
        setActiveMode: @escaping @MainActor (WorkflowMode) async -> Void = { _ in },
        prequitHandler: @escaping @MainActor () async -> Void = {},
        logger: PersonalScribeLogger = AppComposition.makeLogger(PersonalScribeLogCategory.ui)
    ) {
        self.controller = StatusItemController(
            sceneModel: sceneModel,
            appStore: appStore,
            openHome: openHome,
            openTranscriptions: openTranscriptions,
            openSettings: openSettings,
            openCopyLastTranscript: openCopyLastTranscript,
            offlineRetranscriptionAction: offlineRetranscriptionAction,
            isOnboardingCompleteProvider: isOnboardingCompleteProvider,
            inputDeviceProvider: inputDeviceProvider,
            modesProvider: modesProvider,
            setActiveMode: setActiveMode,
            prequitHandler: prequitHandler,
            logger: logger
        )
    }

    var isMenuBarVisible: Bool {
        controller.isStatusItemVisible
    }

    func setMenuBarVisible(_ isVisible: Bool) {
        controller.setStatusItemVisible(isVisible)
    }
}

/// @StateObject host for the Esc-key global monitor. Starts the monitor
/// immediately on init so Esc is wired before the user can trigger a
/// recording.
@MainActor
final class EscapeKeyMonitorHost: ObservableObject {
    let monitor: EscapeKeyMonitor
    private var visibilityCancellable: AnyCancellable?

    /// Esc is armed only while a recording can be cancelled, including
    /// the paused state. It behaves normally in every app otherwise.
    init(monitor: EscapeKeyMonitor, visibility: AnyPublisher<PillOverlayViewModel.Visibility, Never>) {
        self.monitor = monitor
        monitor.start()
        visibilityCancellable = visibility
            .map(Self.shouldArm(for:))
            .removeDuplicates()
            .sink { [weak monitor] armed in monitor?.setArmed(armed) }
    }

    static func shouldArm(for visibility: PillOverlayViewModel.Visibility) -> Bool {
        switch visibility {
        case .recording, .holdToRecord, .paused:
            return true
        case .hidden, .idle, .cancelled, .transcribing, .error, .loading, .downloading:
            return false
        }
    }

    deinit {
        Task { @MainActor [monitor] in
            monitor.stop()
        }
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
