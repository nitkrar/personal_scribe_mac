import AppKit
import Combine
import SwiftUI
import SeshatCore

struct OverlayPanelInteractionState: Equatable {
    private let dragThreshold: CGFloat = 4
    private var mouseDownPoint: NSPoint?
    private(set) var isDragging = false

    mutating func begin(at point: NSPoint) {
        mouseDownPoint = point
        isDragging = false
    }

    mutating func drag(to point: NSPoint) -> Bool {
        guard let mouseDownPoint else {
            return false
        }

        if isDragging {
            return false
        }

        let deltaX = point.x - mouseDownPoint.x
        let deltaY = point.y - mouseDownPoint.y
        let distance = hypot(deltaX, deltaY)
        if distance >= dragThreshold {
            isDragging = true
            return true
        }

        return false
    }

    mutating func end(at point: NSPoint) -> Bool {
        defer {
            mouseDownPoint = nil
            isDragging = false
        }

        guard let mouseDownPoint else {
            return false
        }

        let deltaX = point.x - mouseDownPoint.x
        let deltaY = point.y - mouseDownPoint.y
        let distance = hypot(deltaX, deltaY)
        return !isDragging && distance < dragThreshold
    }
}

final class DraggablePanel: NSPanel {
    override var canBecomeKey: Bool {
        true
    }
}

final class ClickThroughHostingView<Content: View>: NSHostingView<Content> {
    var onMouseDragged: (() -> Void)?
    var onTap: (() -> Void)?
    var isTapEnabled: (() -> Bool)?
    private var interactionState = OverlayPanelInteractionState()

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        interactionState.begin(at: convert(event.locationInWindow, from: nil))
    }

    override func mouseDragged(with event: NSEvent) {
        let localPoint = convert(event.locationInWindow, from: nil)
        let startedDragging = interactionState.drag(to: localPoint)
        if startedDragging {
            onMouseDragged?()
        }

        if interactionState.isDragging {
            window?.performDrag(with: event)
        }
    }

    override func mouseUp(with event: NSEvent) {
        let localPoint = convert(event.locationInWindow, from: nil)
        guard interactionState.end(at: localPoint) else {
            return
        }

        guard isTapEnabled?() == true else {
            return
        }

        onTap?()
    }
}

@MainActor
public final class PillOverlayPresenter {
    private let model: PillOverlayViewModel
    private let onTap: @MainActor () -> Void
    private var panel: DraggablePanel?
    private var visibilityCancellable: AnyCancellable?
    private let diagnosticLogger = SeshatLogger(category: SeshatLogCategory.ui)

    /// Whether the presenter last asked the panel to show itself. Exposed
    /// for tests — NSPanel's real `isVisible` depends on AppKit runtime
    /// state that isn't reliable in unit tests.
    public private(set) var intendsToShow: Bool = false
    /// Panel must be wide enough to hold the widest pill variant
    /// (download / loading — 240pt) plus some slack for shadow / padding.
    /// Height is the 34pt recording-pill height + headroom for the
    /// download pill's two-line layout.
    private let panelSize = NSSize(width: 280, height: 60)
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

            diagnosticLogger.info("PillOverlayPresenter visibility-sink — visibility=\(visibility) isVisible=\(isVisible)")

            switch visibility {
            case .hidden:
                hide()
            case .idle, .downloading, .loading, .recording, .transcribing, .done:
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
        // Deliberately NOT reading `model.visibility` here. `@Published`
        // emits its new value in `willSet`, so during a sink callback
        // `model.visibility` still reflects the *previous* value — reading
        // it here would make the guard use stale state and bounce an
        // intended-visible update back into `hide()` (this was the bug
        // behind the "pill only shows for a split second" regression;
        // diagnostic log 2026-04-18 21:48:57 show the guard firing on
        // visibility=loading and redirecting to hide because the stored
        // value was still .hidden from the prior transition).
        //
        // The sink in the init already dispatches .hidden to hide() in a
        // separate branch, so this method is only ever called when we
        // genuinely want to show — no guard needed.
        intendsToShow = true

        let panelExisted = panel != nil
        let panel = panel ?? makePanel()
        self.panel = panel

        if !hasUserRepositioned {
            updatePanelPosition(panel)
        }

        panel.orderFrontRegardless()
        diagnosticLogger.info("PillOverlayPresenter.show — panelExisted=\(panelExisted) frame=\(panel.frame) isVisible=\(panel.isVisible)")
    }

    public func hide() {
        intendsToShow = false
        panel?.orderOut(nil)
        diagnosticLogger.info("PillOverlayPresenter.hide — panel=\(panel == nil ? "nil" : "exists")")
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

        let contentView = panel.contentView ?? NSView(frame: NSRect(origin: .zero, size: panelSize))
        panel.contentView = contentView

        let hostingView = ClickThroughHostingView(
            rootView: PillOverlayView(model: model)
        )
        hostingView.onMouseDragged = { [weak self] in
            self?.hasUserRepositioned = true
        }
        hostingView.onTap = { [weak self] in
            self?.onTap()
        }
        hostingView.isTapEnabled = { [weak self] in
            self?.supportsTap ?? false
        }
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

    private var supportsTap: Bool {
        switch model.visibility {
        case .idle, .recording:
            return true
        case .hidden, .downloading, .loading, .transcribing, .done:
            return false
        }
    }
}
