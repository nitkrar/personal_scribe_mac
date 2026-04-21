import AppKit
import PersonalScribeCore
import SwiftUI

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
    private let model: UnifiedWindowModel
    private let hostingController: NSHostingController<UnifiedWindowView>
    private let homeViewModel: HomeTabViewModel
    private let transcriptionsViewModel: TranscriptionsTabViewModel
    private let modesViewModel: ModesTabViewModel
    private let microphoneFooterViewModel: MicrophoneFooterViewModel
    private let permissionService: any PermissionService
    private var windowTintObserver: NSObjectProtocol?

    init(
        defaults: UserDefaults = .standard,
        model: UnifiedWindowModel = UnifiedWindowModel(),
        transcriptReader: any TranscriptReading,
        metricsReader: any MetricsReading,
        permissionService: any PermissionService,
        inputDeviceProvider: any AudioInputDeviceProviding,
        modes: [ModeDescriptor] = ModeRegistry.all,
        activeModeProvider: @escaping @MainActor () -> ModeDescriptor? = { nil },
        activeModeStream: (@MainActor () -> AsyncStream<ModeDescriptor?>)? = nil,
        setActiveMode: (@MainActor (ModeDescriptor) async -> Void)? = nil
    ) {
        self.defaults = defaults
        self.model = model
        self.permissionService = permissionService
        self.homeViewModel = HomeTabViewModel(reader: metricsReader)
        self.transcriptionsViewModel = TranscriptionsTabViewModel(reader: transcriptReader)
        self.modesViewModel = ModesTabViewModel(
            modes: modes,
            activeModeProvider: activeModeProvider,
            activeModeStream: activeModeStream,
            setActiveHandler: setActiveMode
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
            modesViewModel: modesViewModel,
            microphoneFooterViewModel: microphoneFooterViewModel,
            permissionService: permissionService,
            defaults: defaults
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

        windowTintObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: defaults,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.applyWindowTint()
            }
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    isolated deinit {
        if let windowTintObserver {
            NotificationCenter.default.removeObserver(windowTintObserver)
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
        if !window.isVisible {
            let activeScreenFrame = UnifiedWindowController.activeScreenVisibleFrame()
            let reconciled = UnifiedWindowController.reconciledFrame(
                for: window.frame,
                activeScreenVisibleFrame: activeScreenFrame
            )
            if reconciled != window.frame {
                window.setFrame(reconciled, display: false)
            }
        }

        super.showWindow(sender)
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
            modesViewModel: modesViewModel,
            microphoneFooterViewModel: microphoneFooterViewModel,
            permissionService: permissionService,
            defaults: defaults
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
