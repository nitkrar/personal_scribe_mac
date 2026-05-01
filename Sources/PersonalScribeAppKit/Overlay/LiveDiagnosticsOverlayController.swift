import AppKit
import SwiftUI
import PersonalScribeCore

@MainActor
protocol LiveDiagnosticsOverlayPaneling: AnyObject {
    var isVisible: Bool { get }
    func orderFrontRegardless()
    func orderOut(_ sender: Any?)
    func setFrameOrigin(_ point: NSPoint)
    func setContentSize(_ size: NSSize)
    func setContentView(_ view: NSView)
}

extension NSPanel: LiveDiagnosticsOverlayPaneling {
    func setContentView(_ view: NSView) {
        contentView = view
    }
}

@MainActor
protocol LiveDiagnosticsOverlayPanelBuilding {
    func makePanel(
        initialSize: NSSize,
        dismissAction: @escaping () -> Void
    ) -> any LiveDiagnosticsOverlayPaneling
}

@MainActor
struct AppKitLiveDiagnosticsOverlayPanelBuilder: LiveDiagnosticsOverlayPanelBuilding {
    func makePanel(
        initialSize: NSSize,
        dismissAction: @escaping () -> Void
    ) -> any LiveDiagnosticsOverlayPaneling {
        let panel = LiveDiagnosticsOverlayPanel(
            contentRect: NSRect(origin: .zero, size: initialSize),
            styleMask: [.titled, .utilityWindow, .fullSizeContentView],
            backing: .buffered,
            defer: false,
            dismissAction: dismissAction
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        return panel
    }
}

private final class LiveDiagnosticsOverlayPanel: NSPanel {
    private let dismissAction: () -> Void

    init(
        contentRect: NSRect,
        styleMask: NSWindow.StyleMask,
        backing: NSWindow.BackingStoreType,
        defer flag: Bool,
        dismissAction: @escaping () -> Void
    ) {
        self.dismissAction = dismissAction
        super.init(
            contentRect: contentRect,
            styleMask: styleMask,
            backing: backing,
            defer: flag
        )
    }

    override var canBecomeKey: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        dismissAction()
    }
}

@MainActor
final class LiveDiagnosticsOverlayController: ObservableObject {
    private let defaults: UserDefaults
    private let notificationCenter: NotificationCenter
    private let store: DiagnosticsStore
    private let panel: any LiveDiagnosticsOverlayPaneling
    let viewModel: LiveDiagnosticsOverlayViewModel
    private let panelSize = NSSize(width: 480, height: 320)

    private var defaultsDidChangeObserver: NSObjectProtocol?
    private var storeObservationTask: Task<Void, Never>?

    init(
        store: DiagnosticsStore,
        defaults: UserDefaults = .standard,
        notificationCenter: NotificationCenter = .default,
        panelBuilder: any LiveDiagnosticsOverlayPanelBuilding = AppKitLiveDiagnosticsOverlayPanelBuilder()
    ) {
        self.store = store
        self.defaults = defaults
        self.notificationCenter = notificationCenter
        let dismissAction: () -> Void = { [defaults] in
            ShowLiveDiagnosticsOverlayPreference.persist(false, to: defaults)
        }
        viewModel = LiveDiagnosticsOverlayViewModel(dismissAction: dismissAction)
        panel = panelBuilder.makePanel(initialSize: panelSize, dismissAction: dismissAction)

        configurePanel()
        startObservingDiagnostics()
        startObservingPreferences()
        refreshVisibility()
    }

    isolated deinit {
        storeObservationTask?.cancel()
        if let defaultsDidChangeObserver {
            notificationCenter.removeObserver(defaultsDidChangeObserver)
        }
    }

    var currentEvents: [RedactedDiagnosticsEvent] {
        viewModel.events
    }

    var isPanelVisible: Bool {
        panel.isVisible
    }

    private func configurePanel() {
        panel.setContentSize(panelSize)
        panel.setContentView(
            NSHostingView(
                rootView: LiveDiagnosticsOverlayView(viewModel: viewModel)
            )
        )
        positionPanel()
    }

    private func startObservingDiagnostics() {
        storeObservationTask = Task { [weak self, store] in
            let stream = await store.stream()
            for await events in stream {
                await MainActor.run {
                    self?.viewModel.update(events: events)
                }
            }
        }
    }

    private func startObservingPreferences() {
        defaultsDidChangeObserver = notificationCenter.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: defaults,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refreshVisibility()
            }
        }
    }

    private func refreshVisibility() {
        let shouldShow = DiagnosticLoggingMode.resolve(from: defaults) == .verbose
            && ShowLiveDiagnosticsOverlayPreference.resolve(from: defaults)

        if shouldShow {
            positionPanel()
            panel.orderFrontRegardless()
        } else if panel.isVisible {
            panel.orderOut(nil)
        }
    }

    private func positionPanel() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else {
            return
        }

        let visibleFrame = screen.visibleFrame
        let origin = NSPoint(
            x: max(visibleFrame.minX + 24, visibleFrame.maxX - panelSize.width - 24),
            y: max(visibleFrame.minY + 24, visibleFrame.maxY - panelSize.height - 48)
        )
        panel.setContentSize(panelSize)
        panel.setFrameOrigin(origin)
    }
}
