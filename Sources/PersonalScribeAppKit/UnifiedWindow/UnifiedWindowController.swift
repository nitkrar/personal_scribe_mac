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
    private let permissionService: any PermissionService
    private var windowTintObserver: NSObjectProtocol?

    init(
        defaults: UserDefaults = .standard,
        model: UnifiedWindowModel = UnifiedWindowModel(),
        transcriptReader: any TranscriptReading,
        metricsReader: any MetricsReading,
        permissionService: any PermissionService,
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

        let initialTint = WindowTint.resolve(from: defaults)
        let rootView = UnifiedWindowView(
            model: model,
            windowTint: initialTint,
            homeViewModel: homeViewModel,
            transcriptionsViewModel: transcriptionsViewModel,
            modesViewModel: modesViewModel,
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
        guard let window else { return }

        if !window.isVisible {
            window.center()
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
