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
    private let logger: PersonalScribeLogger
    private var windowTintObserver: NSObjectProtocol?
    private var appDidBecomeActiveObserver: NSObjectProtocol?
    private var appDidResignActiveObserver: NSObjectProtocol?
    private var activeSpaceDidChangeObserver: NSObjectProtocol?
    private var foregroundRecoveryState = UnifiedWindowForegroundRecoveryState()
    private var frameMutationSource: String?
    private var lastObservedWindowFrame: NSRect?

    init(
        defaults: UserDefaults = .standard,
        notificationCenter: NotificationCenter = .default,
        workspaceNotificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
        model: UnifiedWindowModel = UnifiedWindowModel(),
        transcriptReader: any TranscriptReading,
        metricsStore: MetricsSnapshotStore,
        permissionService: any PermissionService,
        inputDeviceProvider: any AudioInputDeviceProviding,
        modes: [WorkflowMode] = WorkflowModeRegistry.builtInModes,
        modelService: ActiveModelService,
        offlineTranscriptionCoordinator: (any OfflineTranscriptionJobManaging)? = nil,
        offlineRetranscriptionAction: OfflineRetranscriptionAction? = nil,
        setActiveMode: (@MainActor (WorkflowMode) async -> Void)? = nil,
        menuBarVisibilityProvider: @escaping @MainActor () -> Bool = { true },
        menuBarVisibilitySetter: @escaping @MainActor (Bool) -> Void = { _ in },
        openDiagnosticsWindow: @escaping @MainActor () -> Void = {},
        logger: PersonalScribeLogger
    ) {
        self.defaults = defaults
        self.notificationCenter = notificationCenter
        self.workspaceNotificationCenter = workspaceNotificationCenter
        self.model = model
        self.permissionService = permissionService
        self.menuBarVisibilityProvider = menuBarVisibilityProvider
        self.menuBarVisibilitySetter = menuBarVisibilitySetter
        self.openDiagnosticsWindow = openDiagnosticsWindow
        self.logger = logger
        self.homeViewModel = HomeTabViewModel(metrics: metricsStore, defaults: defaults)
        self.transcriptionsViewModel = TranscriptionsTabViewModel(
            reader: transcriptReader,
            offlineRetranscriptionAction: offlineRetranscriptionAction
        )
        self.offlineTranscriptionViewModel = OfflineTranscriptionTabViewModel(
            transcriptReader: transcriptReader,
            coordinator: offlineTranscriptionCoordinator,
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
        // `.fullScreenAuxiliary` lets the window surface over a full-screen
        // app without a space switch. `.moveToActiveSpace` is added only while
        // opening (see `showWindow`). Deliberately do NOT set
        // `.canJoinAllSpaces` / `.stationary` — those are pill-overlay
        // pinning flags that would pin the window to one space (#041).
        window.collectionBehavior = [.fullScreenAuxiliary]

        super.init(window: window)

        window.delegate = self
        lastObservedWindowFrame = window.frame

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

        let frameBeforeShow = window.frame
        logWindowState(
            event: "show_begin",
            path: "showWindow",
            source: "ours",
            oldFrame: frameBeforeShow,
            newFrame: frameBeforeShow
        )

        // Bug #041: preserve valid placement on any attached display,
        // constrain partially off-screen placement to that display, and
        // re-center only a fully stranded frame.
        reconcileWindowFrameIfNeeded(
            window,
            whenVisible: false,
            path: "showWindow"
        )

        // Join the current space while opening (#041), then stop following:
        // a window that always follows the active space isn't treated as part
        // of a desktop, so macOS buries it on return to that desktop (#101).
        window.collectionBehavior.insert(.moveToActiveSpace)
        super.showWindow(sender)
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        logWindowState(
            event: "show_end",
            path: "showWindow",
            source: "ours",
            oldFrame: frameBeforeShow,
            newFrame: window.frame
        )
        DispatchQueue.main.async { [weak self, weak window] in
            guard let self, let window else { return }
            let oldFrame = window.frame
            window.collectionBehavior.remove(.moveToActiveSpace)
            self.logWindowState(
                event: "move_to_active_space_removed",
                path: "showWindow.async",
                source: "ours",
                oldFrame: oldFrame,
                newFrame: window.frame
            )
        }
    }

    /// Convenience for menu-bar / hotkey entry points that want to
    /// pre-select a tab when opening the window.
    func showWindow(selecting tab: AppTab) {
        model.setActiveTab(tab)
        showWindow(nil)
    }

    static func reconciledFrame(
        for windowFrame: NSRect,
        activeScreenVisibleFrame: NSRect
    ) -> NSRect {
        reconciledFrame(
            for: windowFrame,
            activeScreenVisibleFrame: activeScreenVisibleFrame,
            availableScreenVisibleFrames: [activeScreenVisibleFrame]
        )
    }

    /// Preserves valid placement on any display, constrains a partially
    /// visible frame to its display, and centers a stranded frame on the
    /// active display. The window size is preserved.
    static func reconciledFrame(
        for windowFrame: NSRect,
        activeScreenVisibleFrame: NSRect,
        availableScreenVisibleFrames: [NSRect]
    ) -> NSRect {
        guard activeScreenVisibleFrame != .zero else {
            return windowFrame
        }

        let visibleFrames = availableScreenVisibleFrames.filter { $0 != .zero }
        if visibleFrames.contains(where: { $0.contains(windowFrame) }) {
            return windowFrame
        }

        let intersectingFrame = visibleFrames.max { lhs, rhs in
            intersectionArea(of: windowFrame, and: lhs)
                < intersectionArea(of: windowFrame, and: rhs)
        }
        if let intersectingFrame,
           intersectionArea(of: windowFrame, and: intersectingFrame) > 0 {
            return frame(windowFrame, constrainedTo: intersectingFrame)
        }

        return NSRect(
            x: activeScreenVisibleFrame.midX - (windowFrame.width / 2.0),
            y: activeScreenVisibleFrame.midY - (windowFrame.height / 2.0),
            width: windowFrame.width,
            height: windowFrame.height
        )
    }

    private static func intersectionArea(of lhs: NSRect, and rhs: NSRect) -> CGFloat {
        let intersection = lhs.intersection(rhs)
        guard !intersection.isNull else { return 0 }
        return intersection.width * intersection.height
    }

    private static func frame(_ frame: NSRect, constrainedTo target: NSRect) -> NSRect {
        let x: CGFloat
        if frame.width <= target.width {
            x = min(max(frame.minX, target.minX), target.maxX - frame.width)
        } else {
            x = target.midX - (frame.width / 2.0)
        }

        let y: CGFloat
        if frame.height <= target.height {
            y = min(max(frame.minY, target.minY), target.maxY - frame.height)
        } else {
            y = target.midY - (frame.height / 2.0)
        }

        return NSRect(x: x, y: y, width: frame.width, height: frame.height)
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
        let frameBeforeRecovery = window.frame
        logWindowState(
            event: "recover_begin",
            path: "recoverForegroundIfNeeded",
            source: "ours",
            oldFrame: frameBeforeRecovery,
            newFrame: frameBeforeRecovery
        )
        guard foregroundRecoveryState.consumeRestoreRequest(
            appIsActive: NSApplication.shared.isActive,
            unifiedWindowIsVisible: window.isVisible
        ) else {
            logWindowState(
                event: "recover_skipped",
                path: "recoverForegroundIfNeeded",
                source: "ours",
                oldFrame: frameBeforeRecovery,
                newFrame: window.frame
            )
            return
        }

        reconcileWindowFrameIfNeeded(
            window,
            whenVisible: true,
            path: "recoverForegroundIfNeeded"
        )
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        logWindowState(
            event: "recover_end",
            path: "recoverForegroundIfNeeded",
            source: "ours",
            oldFrame: frameBeforeRecovery,
            newFrame: window.frame
        )
    }

    private func reconcileWindowFrameIfNeeded(
        _ window: NSWindow,
        whenVisible shouldRunForVisibleWindow: Bool,
        path: String
    ) {
        let oldFrame = window.frame
        guard shouldRunForVisibleWindow || !window.isVisible else {
            logWindowState(
                event: "reconcile_skipped_visible",
                path: path,
                source: "ours",
                oldFrame: oldFrame,
                newFrame: oldFrame
            )
            return
        }

        let activeScreenFrame = UnifiedWindowController.activeScreenVisibleFrame()
        let reconciled = UnifiedWindowController.reconciledFrame(
            for: window.frame,
            activeScreenVisibleFrame: activeScreenFrame,
            availableScreenVisibleFrames: NSScreen.screens.map(\.visibleFrame)
        )
        if reconciled != window.frame {
            logWindowState(
                event: "set_frame_begin",
                path: path,
                source: "ours",
                oldFrame: oldFrame,
                newFrame: reconciled,
                activeTargetVisibleFrame: activeScreenFrame
            )
            frameMutationSource = "ours:\(path).setFrame"
            window.setFrame(reconciled, display: false)
            frameMutationSource = nil
            lastObservedWindowFrame = window.frame
            logWindowState(
                event: "set_frame_end",
                path: path,
                source: "ours",
                oldFrame: oldFrame,
                newFrame: window.frame,
                activeTargetVisibleFrame: activeScreenFrame
            )
        } else {
            logWindowState(
                event: "reconcile_unchanged",
                path: path,
                source: "ours",
                oldFrame: oldFrame,
                newFrame: oldFrame,
                activeTargetVisibleFrame: activeScreenFrame
            )
        }
    }

    private func logWindowState(
        event: String,
        path: String,
        source: String,
        oldFrame: NSRect,
        newFrame: NSRect,
        activeTargetVisibleFrame: NSRect? = nil
    ) {
        let screens = NSScreen.screens
        let mouseLocation = NSEvent.mouseLocation
        let mouseScreen = screens.first { $0.frame.contains(mouseLocation) }
        let windowScreen = window?.screen
        let target = activeTargetVisibleFrame.map(Self.describe) ?? "nil"
        let allScreens = screens.enumerated().map { index, screen in
            "\(index):frame=\(Self.describe(screen.frame)),visible=\(Self.describe(screen.visibleFrame))"
        }.joined(separator: "|")

        logger.debug(
            "unified_window_frame event=\(event) path=\(path) source=\(source) "
            + "old=\(Self.describe(oldFrame)) new=\(Self.describe(newFrame)) "
            + "windowScreenFrame=\(Self.describe(windowScreen?.frame)) "
            + "windowScreenVisible=\(Self.describe(windowScreen?.visibleFrame)) "
            + "mouse=\(NSStringFromPoint(mouseLocation)) "
            + "mouseScreenFrame=\(Self.describe(mouseScreen?.frame)) "
            + "mouseScreenVisible=\(Self.describe(mouseScreen?.visibleFrame)) "
            + "mainScreenFrame=\(Self.describe(NSScreen.main?.frame)) "
            + "mainScreenVisible=\(Self.describe(NSScreen.main?.visibleFrame)) "
            + "activeTargetVisible=\(target) screens=[\(allScreens)] "
            + "isOnActiveSpace=\(window?.isOnActiveSpace ?? false) "
            + "collectionBehavior=\(window?.collectionBehavior.rawValue ?? 0)"
        )
    }

    private static func describe(_ rect: NSRect?) -> String {
        rect.map(NSStringFromRect) ?? "nil"
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

extension UnifiedWindowController: NSWindowDelegate {
    func windowDidMove(_ notification: Notification) {
        guard let movedWindow = notification.object as? NSWindow,
              movedWindow === window else {
            return
        }

        let oldFrame = lastObservedWindowFrame ?? movedWindow.frame
        logWindowState(
            event: "did_move",
            path: "NSWindowDelegate.windowDidMove",
            source: frameMutationSource ?? "system",
            oldFrame: oldFrame,
            newFrame: movedWindow.frame
        )
        lastObservedWindowFrame = movedWindow.frame
    }

    func windowDidChangeScreen(_ notification: Notification) {
        guard let changedWindow = notification.object as? NSWindow,
              changedWindow === window else {
            return
        }

        let oldFrame = lastObservedWindowFrame ?? changedWindow.frame
        logWindowState(
            event: "did_change_screen",
            path: "NSWindowDelegate.windowDidChangeScreen",
            source: frameMutationSource ?? "system",
            oldFrame: oldFrame,
            newFrame: changedWindow.frame
        )
        lastObservedWindowFrame = changedWindow.frame
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
