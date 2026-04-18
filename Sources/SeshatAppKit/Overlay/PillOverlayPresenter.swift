import AppKit
import Combine
import SwiftUI
import SeshatCore

@MainActor
public final class PillOverlayPresenter {
    private let model: PillOverlayViewModel
    private let onTap: @MainActor () -> Void
    private var panel: NSPanel?
    private var visibilityCancellable: AnyCancellable?
    private let panelSize = NSSize(width: 220, height: 44)

    public init(
        model: PillOverlayViewModel,
        onTap: @escaping @MainActor () -> Void = {}
    ) {
        self.model = model
        self.onTap = onTap
        visibilityCancellable = model.$visibility.sink { [weak self] visibility in
            guard let self else {
                return
            }

            switch visibility {
            case .hidden:
                hide()
            case .downloading, .recording, .transcribing:
                if !isVisible {
                    show()
                }
            }
        }
    }

    public var isVisible: Bool {
        panel != nil
    }

    public func show() {
        guard model.visibility != .hidden else {
            hide()
            return
        }

        let panel = panel ?? makePanel()
        self.panel = panel

        updatePanelPosition(panel)
        panel.orderFrontRegardless()
    }

    public func hide() {
        panel?.close()
        panel = nil
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.canHide = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        panel.ignoresMouseEvents = false
        panel.contentView = NSHostingView(
            rootView: PillOverlayView(model: model, onTap: onTap)
        )

        return panel
    }

    private func updatePanelPosition(_ panel: NSPanel) {
        let screenFrame = NSScreen.main?.visibleFrame ?? .zero
        let x = screenFrame.midX - panel.frame.width / 2
        let y = screenFrame.minY + 64

        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}
