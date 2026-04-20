import AppKit
import PersonalScribeCore
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController {
    private let defaults: UserDefaults
    private var windowTintObserver: NSObjectProtocol?

    init(
        defaults: UserDefaults = .standard,
        menuBarVisibilityProvider: @escaping @MainActor () -> Bool = { true },
        menuBarVisibilitySetter: @escaping @MainActor (Bool) -> Void = { _ in }
    ) {
        self.defaults = defaults
        let rootView = SettingsView(
            defaults: defaults,
            menuBarVisibilityProvider: menuBarVisibilityProvider,
            menuBarVisibilitySetter: menuBarVisibilitySetter
        )
        let hostingController = NSHostingController(rootView: rootView)
        let window = NSWindow(contentViewController: hostingController)
        window.setContentSize(
            NSSize(
                width: SettingsLayout.windowWidth,
                height: SettingsLayout.windowHeight
            )
        )
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.isReleasedWhenClosed = false
        window.title = "\(AppBrand.displayName) Settings"
        let tint = WindowTint.resolve(from: defaults)
        window.appearance = tint.forcesDarkMode ? NSAppearance(named: .darkAqua) : nil

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

    private func applyWindowTint() {
        guard let window else { return }
        let tint = WindowTint.resolve(from: defaults)
        window.appearance = tint.forcesDarkMode ? NSAppearance(named: .darkAqua) : nil
    }
}

@MainActor
final class SettingsWindowControllerHost: ObservableObject {
    private let controllerFactory: @MainActor () -> SettingsWindowController
    private var controller: SettingsWindowController?

    init(
        controllerFactory: @escaping @MainActor () -> SettingsWindowController = {
            SettingsWindowController()
        }
    ) {
        self.controllerFactory = controllerFactory
    }

    func showWindow(_ sender: Any? = nil) {
        if controller == nil {
            controller = controllerFactory()
        }

        controller?.showWindow(sender)
    }
}
