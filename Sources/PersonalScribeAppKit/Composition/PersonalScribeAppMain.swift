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

        // Pill UX Phase 6: global Esc cancels an active recording and
        // surfaces the Cancel Card. Guarded against firing outside the
        // recording / hold-to-record states so Esc elsewhere (dialogs,
        // text fields, other apps) stays intercept-free.
        //
        // Caveat: `coordinator.toggle()` below stops capture via the
        // normal transcribe path — the audio will still be transcribed
        // and auto-pasted. A follow-up phase will add a true
        // `SessionCoordinator.cancelRecording()` that discards audio
        // without transcribing. Until then, the Cancel Card's Undo
        // restores the user's pre-recording clipboard (Phase 5), so
        // the worst-case UX is "pasted the transcript + user clicked
        // Undo to undo the paste".
        let escapeKeyMonitor = EscapeKeyMonitor { [weak pillController, weak coordinator] in
            guard let pillController else { return }
            let visibility = pillController.viewModel.visibility
            guard visibility == .holdToRecord || visibility == .recording else {
                return
            }
            pillController.viewModel.cancel()
            Task { [weak coordinator] in
                await coordinator?.toggle()
            }
        }

        // Hotkey monitor construction is deferred until AFTER the pill
        // controller exists so `onHoldStartVisibilityPush` can capture
        // the view model reference directly and push `.holdToRecord`
        // on hold-start. Order-dependent: pillController must be ready
        // before the startup coordinator schedules the monitor start.
        let startupCoordinator = startupCoordinator
            ?? AppComposition.makeStartupCoordinator(
                coordinator: coordinator,
                hotkeyMonitor: AppComposition.makeGlobalHotkeyMonitor(
                    permissionService: appPermissionService,
                    coordinator: coordinator,
                    onHoldStartVisibilityPush: { [weak pillController] in
                        pillController?.viewModel.apply(visibility: .holdToRecord)
                    }
                )
            )
        self.startupCoordinator = startupCoordinator
        let metricsReader: any MetricsReading = {
            do {
                return try AppComposition.makeMetricsReader()
            } catch {
                return EmptyMetricsReader()
            }
        }()
        let unifiedTranscriptReader = PersonalScribeAppMain.defaultTranscriptReader()
        let appKitActiveModeProvider = AppComposition.activeModeProvider
        let modelService = AppComposition.modelService
        let unifiedWindowControllerHost = UnifiedWindowControllerHost(
            controllerFactory: {
                UnifiedWindowController(
                    defaults: defaults,
                    transcriptReader: unifiedTranscriptReader,
                    metricsReader: metricsReader,
                    permissionService: appPermissionService,
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
        let pasteLastTranscriptAction = PasteLastTranscriptAction(
            transcriptReader: unifiedTranscriptReader,
            outputService: resolvedOutputService
        )
        let statusItemControllerHost = StatusItemControllerHost(
            sceneModel: sceneModel,
            appStore: appStore,
            openHome: openHomeTab,
            openPasteLastTranscript: {
                Task { await pasteLastTranscriptAction.perform() }
            },
            isOnboardingCompleteProvider: isOnboardingCompleteProvider,
            inputDeviceProvider: AVFoundationInputDeviceProvider(defaults: defaults)
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
        },
        inputDeviceProvider: (any AudioInputDeviceProviding)? = nil
    ) {
        self.controller = StatusItemController(
            sceneModel: sceneModel,
            appStore: appStore,
            openHome: openHome,
            openPasteLastTranscript: openPasteLastTranscript,
            openCheckForUpdates: openCheckForUpdates,
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
