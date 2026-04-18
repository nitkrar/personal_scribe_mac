import AppKit
import SwiftUI
import SeshatCore

@MainActor
public final class PillOverlayPresenter {
    private let model: PillOverlayViewModel
    private var panel: NSPanel?
    private let panelSize = NSSize(width: 160, height: 40)

    public init(model: PillOverlayViewModel) {
        self.model = model
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
        panel.ignoresMouseEvents = true
        panel.contentView = NSHostingView(rootView: PillOverlayView(model: model))

        return panel
    }

    private func updatePanelPosition(_ panel: NSPanel) {
        let visibleFrame = (NSScreen.main ?? panel.screen ?? NSScreen.screens.first)?.visibleFrame
            ?? NSRect(origin: .zero, size: panelSize)
        let origin = NSPoint(
            x: visibleFrame.midX - (panelSize.width / 2),
            y: visibleFrame.maxY - 80 - panelSize.height
        )

        panel.setFrame(NSRect(origin: origin, size: panelSize), display: false)
    }
}
