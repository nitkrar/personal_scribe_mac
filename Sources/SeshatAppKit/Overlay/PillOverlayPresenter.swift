import AppKit
import Combine
import SwiftUI
import SeshatCore

fileprivate final class DraggablePanel: NSPanel {
    var onMouseDragged: (() -> Void)?

    override var canBecomeKey: Bool {
        false
    }

    override func mouseDragged(with event: NSEvent) {
        onMouseDragged?()
        performDrag(with: event)
    }
}

fileprivate final class ClickThroughHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }
}

@MainActor
public final class PillOverlayPresenter {
    private let model: PillOverlayViewModel
    private let onTap: @MainActor () -> Void
    private var panel: DraggablePanel?
    private var visibilityCancellable: AnyCancellable?
    private let panelSize = NSSize(width: 220, height: 44)
    private var hasUserRepositioned = false

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
            case .idle, .downloading, .recording, .transcribing:
                if !isVisible {
                    show()
                }
            }
        }
    }

    public var isVisible: Bool {
        panel?.isVisible == true
    }

    public func show() {
        guard model.visibility != .hidden else {
            hide()
            return
        }

        let panel = panel ?? makePanel()
        self.panel = panel

        if !hasUserRepositioned {
            updatePanelPosition(panel)
        }

        panel.orderFrontRegardless()
    }

    public func hide() {
        panel?.orderOut(nil)
    }

    private func makePanel() -> DraggablePanel {
        let panel = DraggablePanel(
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
        panel.onMouseDragged = { [weak self] in
            self?.hasUserRepositioned = true
        }

        let contentView = panel.contentView ?? NSView(frame: NSRect(origin: .zero, size: panelSize))
        panel.contentView = contentView

        let hostingView = ClickThroughHostingView(
            rootView: PillOverlayView(model: model, onTap: onTap)
        )
        hostingView.frame = contentView.bounds
        hostingView.autoresizingMask = [.width, .height]
        contentView.addSubview(hostingView)

        return panel
    }

    private func updatePanelPosition(_ panel: NSPanel) {
        let screenFrame = NSScreen.main?.visibleFrame ?? .zero
        let x = screenFrame.midX - panel.frame.width / 2
        let y = screenFrame.minY + 64

        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}
