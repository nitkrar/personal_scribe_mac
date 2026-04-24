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

    @StateObject private var sceneModel: MenuBarSceneModel
    @StateObject private var pillController: PillOverlayController
    @StateObject private var statusItemController: StatusItemControllerHost
    @StateObject private var unifiedWindowController: UnifiedWindowControllerHost
    @StateObject private var pasteboardSnapshotHost: PasteboardSnapshotHost
    @StateObject private var escapeKeyMonitorHost: EscapeKeyMonitorHost

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
        var clipboardOnlyNotice: (@MainActor () -> Void)?
        let onboardingCompletionPreference = Self.onboardingCompletionPreference(defaults: defaults)
        let isOnboardingCompleteProvider: @MainActor () -> Bool = {
            onboardingCompletionPreference.resolve()
        }

        self.coordinator = coordinator
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

        // Pill UX Phase 5: snapshot the user's pre-recording clipboard
        // contents when recording starts so the Cancel Card's Undo
        // button can restore them if the user discards the recording.
        // Hook into session state transitions via the app store. The
        // `PasteboardSnapshotHost` @StateObject owns the subscription
        // lifetime — attaching cancellables to the struct itself
        // wouldn't survive SwiftUI init re-runs.
        let pasteboardSnapshotHost = PasteboardSnapshotHost(
            appStore: appStore,
            viewModel: pillController.viewModel
        )

        // #002: global Esc truly discards an active recording — no
        // transcribe, no paste. Guarded against firing outside the
        // recording / hold-to-record states so Esc elsewhere (dialogs,
        // text fields, other apps) stays intercept-free. The pill's
        // Cancel Card still fires via `viewModel.cancel()` for the
        // visual feedback; the Phase 5 pasteboard snapshot Undo
        // restore is a no-op on this path (no paste occurred) but
        // stays wired for compatibility. #070 will reshape the pill
        // affordances around pause/resume.
        let escapeKeyMonitor = EscapeKeyMonitor { [weak pillController, weak coordinator] in
            guard let pillController else { return }
            let visibility = pillController.viewModel.visibility
            guard visibility == .holdToRecord || visibility == .recording else {
                return
            }
            pillController.viewModel.cancel()
            Task { [weak coordinator] in
                await coordinator?.cancelIfActive()
            }
        }

        // #071: hold-start now routes through `coordinator.startHoldIfIdle()`
        // which publishes `.holdRecording` eagerly to the pipeline.
        // `AppStore.derivePillVisibility` maps that to `.holdToRecord`
        // for the pill overlay — no side-channel push needed.
        let startupCoordinator = startupCoordinator
            ?? AppComposition.makeStartupCoordinator(
                coordinator: coordinator,
                hotkeyMonitor: AppComposition.makeGlobalHotkeyMonitor(
                    permissionService: appPermissionService,
                    coordinator: coordinator
                )
            )
        self.startupCoordinator = startupCoordinator
        let metricsReader: any MetricsReading = {
            guard let appDatabase = AppComposition.appDatabase else {
                return EmptyMetricsReader()
            }
            return SQLiteMetricsService(
                appDatabase: appDatabase,
                referenceDateProvider: Date.init
            )
        }()
        let unifiedTranscriptReader = PersonalScribeAppMain.defaultTranscriptReader()
        let appKitActiveModeProvider = AppComposition.activeModeProvider
        let modelService = AppComposition.modelService
        // Shared input-device provider — one `AVFoundationInputDeviceProvider`
        // instance backs both the menu-bar Microphone submenu AND the
        // unified-window sidebar footer readout (#008). The provider is
        // stateless (reads from AVFoundation + UserDefaults on each pull)
        // so sharing is safe and keeps both surfaces in sync.
        let inputDeviceProvider: any AudioInputDeviceProviding =
            AVFoundationInputDeviceProvider(defaults: defaults)
        let unifiedWindowControllerHost = UnifiedWindowControllerHost(
            controllerFactory: {
                UnifiedWindowController(
                    defaults: defaults,
                    transcriptReader: unifiedTranscriptReader,
                    metricsReader: metricsReader,
                    permissionService: appPermissionService,
                    inputDeviceProvider: inputDeviceProvider,
                    modes: ModeRegistry.all,
                    activeModeProvider: { appKitActiveModeProvider.currentActiveMode() },
                    activeModeStream: { appKitActiveModeProvider.activeModeStream() },
                    setActiveMode: { mode in
                        do {
                            try await modelService.setActive(modelService.descriptor(for: mode))
                        } catch {
                            PersonalScribeLogger(category: PersonalScribeLogCategory.ui)
                                .error("Failed to set active mode '\(mode.id)'", error: error)
                        }
                    }
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
        let copyLastTranscriptLogger = PersonalScribeLogger(category: PersonalScribeLogCategory.ui)
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
        let statusItemControllerHost = StatusItemControllerHost(
            sceneModel: sceneModel,
            appStore: appStore,
            openHome: openHomeTab,
            openTranscriptions: openTranscriptionsTab,
            openSettings: openSettingsTab,
            openCopyLastTranscript: {
                Task { await copyLastTranscriptAction.perform() }
            },
            isOnboardingCompleteProvider: isOnboardingCompleteProvider,
            inputDeviceProvider: inputDeviceProvider
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
        _pasteboardSnapshotHost = StateObject(
            wrappedValue: pasteboardSnapshotHost
        )
        _escapeKeyMonitorHost = StateObject(
            wrappedValue: EscapeKeyMonitorHost(monitor: escapeKeyMonitor)
        )

        sceneModel.startObserving()
        startupCoordinator.start()

        // #015: watch the permission service and flip
        // `OnboardingCompleted` the first time Mic + Input Monitoring
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

        // First-launch onboarding routing: if permissions haven't been
        // granted yet, auto-open the unified window to the Settings tab
        // so the Permissions sub-tab is one click away. Replaces the
        // pre-M4 OnboardingWindowController auto-open.
        //
        // Re-read after `observer.start()` — the observer may have
        // flipped the flag synchronously on init if perms were already
        // granted (common on re-install), in which case we skip the
        // auto-open.
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
        //
        // `.commands { CommandGroup(replacing: .appSettings) }` overrides
        // SwiftUI's default `⌘,` handler so the shortcut opens our real
        // settings surface (the unified window's Settings tab) instead of
        // the empty `Settings { EmptyView() }` window above.
        Settings {
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
        isOnboardingCompleteProvider: @escaping @MainActor () -> Bool = {
            PersonalScribeAppMain.onboardingCompletionPreference(defaults: .standard).resolve()
        },
        inputDeviceProvider: (any AudioInputDeviceProviding)? = nil
    ) {
        self.controller = StatusItemController(
            sceneModel: sceneModel,
            appStore: appStore,
            openHome: openHome,
            openTranscriptions: openTranscriptions,
            openSettings: openSettings,
            openCopyLastTranscript: openCopyLastTranscript,
            isOnboardingCompleteProvider: isOnboardingCompleteProvider,
            inputDeviceProvider: inputDeviceProvider
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

    init(monitor: EscapeKeyMonitor) {
        self.monitor = monitor
        monitor.start()
    }

    deinit {
        Task { @MainActor [monitor] in
            monitor.stop()
        }
    }
}

/// @StateObject host for the `PasteboardSnapshotService` + the Combine
/// subscription that wires `AppStore` session-state transitions to
/// snapshot / clear calls. Pill UX spec §4 requires saving the pre-
/// recording clipboard so the Cancel Card's Undo can restore it.
@MainActor
final class PasteboardSnapshotHost: ObservableObject {
    let service: PasteboardSnapshotService
    private var cancellables: Set<AnyCancellable> = []
    private var previousSessionState: SessionState

    init(
        appStore: AppStore,
        viewModel: PillOverlayViewModel,
        service: PasteboardSnapshotService = PasteboardSnapshotService()
    ) {
        self.service = service
        self.previousSessionState = appStore.snapshot.sessionState

        viewModel.onUndoCancelledRecording = { [weak service] in
            service?.restoreLastSnapshot()
        }

        appStore.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak appStore, weak service] _ in
                MainActor.assumeIsolated {
                    guard let self, let appStore, let service else { return }
                    let next = appStore.snapshot.sessionState
                    defer { self.previousSessionState = next }

                    // Snapshot on idle → recording. Pre-recording user
                    // clipboard contents are what Undo must restore.
                    if case .idle = self.previousSessionState, case .recording = next {
                        service.snapshotCurrentContents()
                    }

                    // Clear on transcribing → idle (successful complete).
                    // A fresh snapshot will be taken on the next recording.
                    if case .transcribing = self.previousSessionState, case .idle = next {
                        service.clearSnapshot()
                    }
                }
            }
            .store(in: &cancellables)
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
