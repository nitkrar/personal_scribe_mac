import AppKit
import PersonalScribeCore
import PersonalScribeSession
import SwiftUI

struct UnifiedWindowForegroundRecoveryState: Equatable {
    private(set) var pendingRestore = false

    mutating func appDidResignActive(
        unifiedWindowIsVisible: Bool,
        unifiedWindowIsKey: Bool,
        unifiedWindowIsMain: Bool
    ) {
        pendingRestore = unifiedWindowIsVisible && (unifiedWindowIsKey || unifiedWindowIsMain)
    }

    mutating func consumeRestoreRequest(
        appIsActive: Bool,
        unifiedWindowIsVisible: Bool
    ) -> Bool {
        guard pendingRestore else {
            return false
        }
        guard unifiedWindowIsVisible else {
            pendingRestore = false
            return false
        }
        guard appIsActive else {
            return false
        }

        pendingRestore = false
        return true
    }
}

/// NSWindowController for the unified NavigationSplitView window.
///
/// Mirrors `SettingsWindowController`'s hosting pattern — a single
/// `NSHostingController<UnifiedWindowView>` wrapped in an `NSWindow` —
/// so the new window integrates with the existing `StatusItemController`
/// / menu-bar routing without needing a SwiftUI `Scene`.
///
/// Observes `AppTheme` + `WindowTint` via
/// `UserDefaults.didChangeNotification` and forwards the current
/// values into the hosted view + NSWindow appearance, so the
/// Appearance picker in Settings updates this window live.
/// `AppTheme` drives the `NSAppearance` (Light/Dark/System); the
/// `WindowTint` stays as a light-mode brand flavor (warm/neutral).
@MainActor
final class UnifiedWindowController: NSWindowController {
    private let defaults: UserDefaults
    private let notificationCenter: NotificationCenter
    private let workspaceNotificationCenter: NotificationCenter
    private let model: UnifiedWindowModel
    private let hostingController: NSHostingController<UnifiedWindowView>
    private let homeViewModel: HomeTabViewModel
    private let transcriptionsViewModel: TranscriptionsTabViewModel
    private let offlineTranscriptionViewModel: OfflineTranscriptionTabViewModel
    private let modesViewModel: ModesListViewModel
    private let microphoneFooterViewModel: MicrophoneFooterViewModel
    private let permissionService: any PermissionService
    private let menuBarVisibilityProvider: @MainActor () -> Bool
    private let menuBarVisibilitySetter: @MainActor (Bool) -> Void
    private let openDiagnosticsWindow: @MainActor () -> Void
    private var windowTintObserver: NSObjectProtocol?
    private var appDidBecomeActiveObserver: NSObjectProtocol?
    private var appDidResignActiveObserver: NSObjectProtocol?
    private var activeSpaceDidChangeObserver: NSObjectProtocol?
    private var foregroundRecoveryState = UnifiedWindowForegroundRecoveryState()

    init(
        defaults: UserDefaults = .standard,
        notificationCenter: NotificationCenter = .default,
        workspaceNotificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
        model: UnifiedWindowModel = UnifiedWindowModel(),
        transcriptReader: any TranscriptReading,
        metricsReader: any MetricsReading,
        permissionService: any PermissionService,
        inputDeviceProvider: any AudioInputDeviceProviding,
        modes: [WorkflowMode] = WorkflowModeRegistry.builtInModes,
        modelService: ActiveModelService,
        offlineTranscriptionCoordinator: (any OfflineTranscriptionCoordinating)? = nil,
        retranscriptionHandler: (any RetranscriptionPerforming)? = nil,
        setActiveMode: (@MainActor (WorkflowMode) async -> Void)? = nil,
        menuBarVisibilityProvider: @escaping @MainActor () -> Bool = { true },
        menuBarVisibilitySetter: @escaping @MainActor (Bool) -> Void = { _ in },
        openDiagnosticsWindow: @escaping @MainActor () -> Void = {}
    ) {
        self.defaults = defaults
        self.notificationCenter = notificationCenter
        self.workspaceNotificationCenter = workspaceNotificationCenter
        self.model = model
        self.permissionService = permissionService
        self.menuBarVisibilityProvider = menuBarVisibilityProvider
        self.menuBarVisibilitySetter = menuBarVisibilitySetter
        self.openDiagnosticsWindow = openDiagnosticsWindow
        self.homeViewModel = HomeTabViewModel(reader: metricsReader)
        self.transcriptionsViewModel = TranscriptionsTabViewModel(
            reader: transcriptReader,
            retranscriptionHandler: retranscriptionHandler
        )
        self.offlineTranscriptionViewModel = OfflineTranscriptionTabViewModel(
            coordinator: offlineTranscriptionCoordinator ?? DisabledOfflineTranscriptionCoordinator(),
            transcriptReader: transcriptReader,
            modelService: modelService,
            defaults: defaults
        )
        self.modesViewModel = ModesListViewModel(
            registry: AppComposition.workflowModeRegistry,
            modelService: modelService
        )
        self.microphoneFooterViewModel = MicrophoneFooterViewModel(
            provider: inputDeviceProvider,
            defaults: defaults
        )

        let initialTint = WindowTint.resolve(from: defaults)
        let rootView = UnifiedWindowView(
            model: model,
            windowTint: initialTint,
            homeViewModel: homeViewModel,
            transcriptionsViewModel: transcriptionsViewModel,
            offlineTranscriptionViewModel: offlineTranscriptionViewModel,
            modesViewModel: modesViewModel,
            microphoneFooterViewModel: microphoneFooterViewModel,
            permissionService: permissionService,
            defaults: defaults,
            menuBarVisibilityProvider: menuBarVisibilityProvider,
            menuBarVisibilitySetter: menuBarVisibilitySetter,
            openDiagnosticsWindow: openDiagnosticsWindow
        )
        let hostingController = NSHostingController(rootView: rootView)
        self.hostingController = hostingController

        let window = NSWindow(contentViewController: hostingController)
        window.setContentSize(
            NSSize(
                width: PersonalScribeTheme.Layout.windowMinWidth,
                height: PersonalScribeTheme.Layout.windowMinHeight
            )
        )
        window.contentMinSize = NSSize(
            width: PersonalScribeTheme.Layout.windowMinWidth,
            height: PersonalScribeTheme.Layout.windowMinHeight
        )
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.isReleasedWhenClosed = false
        window.title = AppBrand.displayName
        let initialTheme = AppTheme.resolve(from: defaults)
        window.appearance = initialTheme.nsAppearance(
            systemIsDark: Self.systemIsDark()
        )
        // Bug #041: without `.moveToActiveSpace` the window re-opens on the
        // space it was last shown on — so triggering Home from the menu bar
        // after a full-screen session warps the user back to that space.
        // `.fullScreenAuxiliary` lets the window surface over any full-screen
        // app without forcing a space switch. Deliberately do NOT set
        // `.canJoinAllSpaces` / `.stationary` — those are pill-overlay
        // pinning flags that would re-create the bug.
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]

        super.init(window: window)

        windowTintObserver = notificationCenter.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: defaults,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.applyWindowTint()
            }
        }

        appDidResignActiveObserver = notificationCenter.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handleAppDidResignActive()
            }
        }

        appDidBecomeActiveObserver = notificationCenter.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.recoverForegroundIfNeeded()
            }
        }

        activeSpaceDidChangeObserver = workspaceNotificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.recoverForegroundIfNeeded()
            }
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    isolated deinit {
        if let windowTintObserver {
            notificationCenter.removeObserver(windowTintObserver)
        }
        if let appDidBecomeActiveObserver {
            notificationCenter.removeObserver(appDidBecomeActiveObserver)
        }
        if let appDidResignActiveObserver {
            notificationCenter.removeObserver(appDidResignActiveObserver)
        }
        if let activeSpaceDidChangeObserver {
            workspaceNotificationCenter.removeObserver(activeSpaceDidChangeObserver)
        }
    }

    override func showWindow(_ sender: Any?) {
        // Poll the provider whenever the unified window is shown —
        // covers hotplug events (USB mic unplugged / plugged while
        // the window was offscreen) without the view model having
        // to observe AVCaptureDevice notifications directly.
        microphoneFooterViewModel.refresh()

        guard let window else { return }

        // Bug #041: if the persisted frame's midpoint isn't on any screen
        // that currently exists (e.g. the user left a multi-monitor setup,
        // or the window is about to be dragged over from a dismissed
        // full-screen space) re-center it on the screen the user is
        // actually looking at. `.moveToActiveSpace` ensures the window
        // follows to the current space; this ensures it lands on-screen.
        reconcileWindowFrameIfNeeded(window, whenVisible: false)

        super.showWindow(sender)
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    /// Convenience for menu-bar / hotkey entry points that want to
    /// pre-select a tab when opening the window.
    func showWindow(selecting tab: AppTab) {
        model.setActiveTab(tab)
        showWindow(nil)
    }

    /// Pure helper (bug #041): if `windowFrame`'s midpoint is already inside
    /// `activeScreenVisibleFrame`, return the frame unchanged. Otherwise
    /// return a copy re-centered over the active screen (preserving size).
    ///
    /// Kept `static` + `internal` so it can be unit-tested without an
    /// NSWindow — NSWindow is `@MainActor` + hard to fake.
    static func reconciledFrame(
        for windowFrame: NSRect,
        activeScreenVisibleFrame: NSRect
    ) -> NSRect {
        if activeScreenVisibleFrame == .zero {
            return windowFrame
        }
        let midpoint = NSPoint(x: windowFrame.midX, y: windowFrame.midY)
        if activeScreenVisibleFrame.contains(midpoint) {
            return windowFrame
        }
        let x = activeScreenVisibleFrame.midX - (windowFrame.width / 2.0)
        let y = activeScreenVisibleFrame.midY - (windowFrame.height / 2.0)
        return NSRect(x: x, y: y, width: windowFrame.width, height: windowFrame.height)
    }

    /// Returns the visible frame of the screen the user is most likely
    /// interacting with — the screen containing the mouse cursor, falling
    /// back to `NSScreen.main`, then `.zero` if nothing is attached.
    static func activeScreenVisibleFrame() -> NSRect {
        let mouseLocation = NSEvent.mouseLocation
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) {
            return screen.visibleFrame
        }
        return NSScreen.main?.visibleFrame ?? .zero
    }

    private func handleAppDidResignActive() {
        guard let window else {
            foregroundRecoveryState.appDidResignActive(
                unifiedWindowIsVisible: false,
                unifiedWindowIsKey: false,
                unifiedWindowIsMain: false
            )
            return
        }

        foregroundRecoveryState.appDidResignActive(
            unifiedWindowIsVisible: window.isVisible,
            unifiedWindowIsKey: window.isKeyWindow,
            unifiedWindowIsMain: window.isMainWindow
        )
    }

    private func recoverForegroundIfNeeded() {
        guard let window else { return }
        guard foregroundRecoveryState.consumeRestoreRequest(
            appIsActive: NSApplication.shared.isActive,
            unifiedWindowIsVisible: window.isVisible
        ) else {
            return
        }

        reconcileWindowFrameIfNeeded(window, whenVisible: true)
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    private func reconcileWindowFrameIfNeeded(
        _ window: NSWindow,
        whenVisible shouldRunForVisibleWindow: Bool
    ) {
        guard shouldRunForVisibleWindow || !window.isVisible else {
            return
        }

        let activeScreenFrame = UnifiedWindowController.activeScreenVisibleFrame()
        let reconciled = UnifiedWindowController.reconciledFrame(
            for: window.frame,
            activeScreenVisibleFrame: activeScreenFrame
        )
        if reconciled != window.frame {
            window.setFrame(reconciled, display: false)
        }
    }

    private func applyWindowTint() {
        let tint = WindowTint.resolve(from: defaults)
        let theme = AppTheme.resolve(from: defaults)
        window?.appearance = theme.nsAppearance(
            systemIsDark: Self.systemIsDark()
        )
        hostingController.rootView = UnifiedWindowView(
            model: model,
            windowTint: tint,
            homeViewModel: homeViewModel,
            transcriptionsViewModel: transcriptionsViewModel,
            offlineTranscriptionViewModel: offlineTranscriptionViewModel,
            modesViewModel: modesViewModel,
            microphoneFooterViewModel: microphoneFooterViewModel,
            permissionService: permissionService,
            defaults: defaults,
            menuBarVisibilityProvider: menuBarVisibilityProvider,
            menuBarVisibilitySetter: menuBarVisibilitySetter,
            openDiagnosticsWindow: openDiagnosticsWindow
        )
    }

    /// Query the current system appearance — returns `true` when the
    /// effective appearance best-matches `.darkAqua`. Used only as the
    /// `systemIsDark` argument to `AppTheme.nsAppearance`, which only
    /// cares about the system flag for `.system` (where it returns
    /// `nil` anyway — the argument is unused in the current impl but
    /// kept for future-proofing).
    private static func systemIsDark() -> Bool {
        NSApplication.shared.effectiveAppearance.bestMatch(
            from: [.aqua, .darkAqua]
        ) == .darkAqua
    }
}

/// `@StateObject`-friendly wrapper so `PersonalScribeAppMain` can own the
/// controller via the same pattern used for Notes / Settings / Onboarding.
@MainActor
final class UnifiedWindowControllerHost: ObservableObject {
    private let controllerFactory: @MainActor () -> UnifiedWindowController
    private var controller: UnifiedWindowController?

    init(
        controllerFactory: @escaping @MainActor () -> UnifiedWindowController
    ) {
        self.controllerFactory = controllerFactory
    }

    func showWindow(_ sender: Any? = nil) {
        if controller == nil {
            controller = controllerFactory()
        }
        controller?.showWindow(sender)
    }

    func showWindow(selecting tab: AppTab) {
        if controller == nil {
            controller = controllerFactory()
        }
        controller?.showWindow(selecting: tab)
    }
}
