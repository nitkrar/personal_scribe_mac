import AppKit
import Combine
import SwiftUI
import PersonalScribeCore

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

@MainActor
final class DraggablePanel: NSPanel {
    private let defaults: UserDefaults
    private let notificationCenter: NotificationCenter
    private var defaultsDidChangeObserver: NSObjectProtocol?

    override var canBecomeKey: Bool {
        true
    }

    override init(
        contentRect: NSRect,
        styleMask style: NSWindow.StyleMask,
        backing backingStoreType: NSWindow.BackingStoreType,
        defer flag: Bool
    ) {
        defaults = .standard
        notificationCenter = .default
        super.init(
            contentRect: contentRect,
            styleMask: style,
            backing: backingStoreType,
            defer: flag
        )
        configurePillAppearanceObservation()
    }

    init(
        contentRect: NSRect,
        styleMask style: NSWindow.StyleMask,
        backing backingStoreType: NSWindow.BackingStoreType,
        defer flag: Bool,
        defaults: UserDefaults = .standard,
        notificationCenter: NotificationCenter = .default
    ) {
        self.defaults = defaults
        self.notificationCenter = notificationCenter
        super.init(
            contentRect: contentRect,
            styleMask: style,
            backing: backingStoreType,
            defer: flag
        )
        configurePillAppearanceObservation()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    isolated deinit {
        if let defaultsDidChangeObserver {
            notificationCenter.removeObserver(defaultsDidChangeObserver)
        }
    }

    private func configurePillAppearanceObservation() {
        applyResolvedAppearance()
        defaultsDidChangeObserver = notificationCenter.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: defaults,
            queue: .main
        ) { [weak self] _ in
            self?.applyResolvedAppearance()
        }
    }

    private func applyResolvedAppearance() {
        let systemIsDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        appearance = PillAppearance.resolve(from: defaults).nsAppearance(systemIsDark: systemIsDark)
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
protocol PillOverlayPaneling: AnyObject {
    var isVisible: Bool { get }
    var frame: NSRect { get }
    var anchorWindow: NSWindow? { get }
    func orderFrontRegardless()
    func orderOut(_ sender: Any?)
    func setFrameOrigin(_ point: NSPoint)
}

extension PillOverlayPaneling {
    var anchorWindow: NSWindow? { nil }
}

extension DraggablePanel: PillOverlayPaneling {
    var anchorWindow: NSWindow? { self }
}

@MainActor
protocol PillOverlayPanelBuilding {
    func makePanel(
        model: PillOverlayViewModel,
        panelSize: NSSize,
        onTap: @escaping @MainActor () -> Void,
        onMouseDragged: @escaping @MainActor () -> Void,
        isTapEnabled: @escaping @MainActor () -> Bool
    ) -> any PillOverlayPaneling
}

struct AppKitPillOverlayPanelBuilder: PillOverlayPanelBuilding {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    @MainActor
    func makePanel(
        model: PillOverlayViewModel,
        panelSize: NSSize,
        onTap: @escaping @MainActor () -> Void,
        onMouseDragged: @escaping @MainActor () -> Void,
        isTapEnabled: @escaping @MainActor () -> Bool
    ) -> any PillOverlayPaneling {
        let panel = DraggablePanel(
            contentRect: NSRect(origin: .zero, size: panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false,
            defaults: defaults
        )

        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        // System shadow off — the pill's SwiftUI view applies a custom
        // shadow AFTER clipShape, which gives a clean rounded edge.
        // Leaving the system shadow on produces the fuzzy fringe around
        // the rounded corners (2026-04-18 dogfood report: "hairy border
        // artefact on the pill").
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.canHide = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        panel.ignoresMouseEvents = false

        let contentView = panel.contentView ?? NSView(frame: NSRect(origin: .zero, size: panelSize))
        panel.contentView = contentView

        let hostingView = ClickThroughHostingView(
            rootView: PillOverlayView(model: model)
        )
        hostingView.onMouseDragged = onMouseDragged
        hostingView.onTap = onTap
        hostingView.isTapEnabled = isTapEnabled
        hostingView.frame = contentView.bounds
        hostingView.autoresizingMask = [.width, .height]
        contentView.addSubview(hostingView)

        return panel
    }
}

@MainActor
public final class PillOverlayPresenter {
    private let model: PillOverlayViewModel
    private let onTap: @MainActor () -> Void
    private let panelBuilder: any PillOverlayPanelBuilding
    private let responseCardBuilder: any ResponseCardBuilding
    private var panel: (any PillOverlayPaneling)?
    private var responseCard: (any ResponseCardPresenting)?
    private var visibilityCancellable: AnyCancellable?
    private let diagnosticLogger = PersonalScribeLogger(category: PersonalScribeLogCategory.ui)
    private static let clipboardOnlyNoticeText = "Copied to clipboard · ⌘V to paste"
    private static let clipboardOnlyNoticeDismissAfter: TimeInterval = 3.0

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

    public convenience init(
        model: PillOverlayViewModel,
        onTap: @escaping @MainActor () -> Void = {}
    ) {
        self.init(
            model: model,
            onTap: onTap,
            panelBuilder: AppKitPillOverlayPanelBuilder(),
            responseCardBuilder: LiveResponseCardBuilder()
        )
    }

    init(
        model: PillOverlayViewModel,
        onTap: @escaping @MainActor () -> Void = {},
        panelBuilder: any PillOverlayPanelBuilding,
        responseCardBuilder: any ResponseCardBuilding = LiveResponseCardBuilder()
    ) {
        self.model = model
        self.onTap = onTap
        self.panelBuilder = panelBuilder
        self.responseCardBuilder = responseCardBuilder
        visibilityCancellable = model.$visibility.sink { [weak self] visibility in
            guard let self else {
                return
            }

            diagnosticLogger.info("PillOverlayPresenter visibility-sink — visibility=\(visibility) isVisible=\(isVisible)")

            switch visibility {
            case .hidden:
                hide()
            case .idle, .downloading, .loading, .recording, .transcribing, .done, .error:
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
        let panel = panel ?? panelBuilder.makePanel(
            model: model,
            panelSize: panelSize,
            onTap: onTap,
            onMouseDragged: { [weak self] in
                self?.hasUserRepositioned = true
            },
            isTapEnabled: { [weak self] in
                self?.supportsTap ?? false
            }
        )
        self.panel = panel

        if !hasUserRepositioned {
            updatePanelPosition(panel)
        }

        panel.orderFrontRegardless()
        diagnosticLogger.info("PillOverlayPresenter.show — panelExisted=\(panelExisted) frame=\(panel.frame) isVisible=\(panel.isVisible)")
    }

    func showClipboardOnlyNotice() {
        guard let anchorWindow = panel?.anchorWindow else {
            diagnosticLogger.info("PillOverlayPresenter.showClipboardOnlyNotice — skipped because no anchor window is available")
            return
        }

        let responseCard = responseCard ?? responseCardBuilder.makeResponseCard()
        self.responseCard = responseCard
        responseCard.show(
            text: Self.clipboardOnlyNoticeText,
            above: anchorWindow,
            autoDismissAfter: Self.clipboardOnlyNoticeDismissAfter
        )
    }

    /// Show a persistent response card above the pill for the "record-
    /// without-transcribe" window — user is recording while the model is
    /// still downloading or loading. The card stays up until
    /// `hideRecordingStatusCard()` is called or replaced via
    /// `updateRecordingStatusCard(text:)`.
    func showRecordingStatusCard(text: String) {
        guard let anchorWindow = panel?.anchorWindow else {
            diagnosticLogger.info("PillOverlayPresenter.showRecordingStatusCard — skipped because no anchor window is available")
            return
        }

        let responseCard = responseCard ?? responseCardBuilder.makeResponseCard()
        self.responseCard = responseCard
        responseCard.show(
            text: text,
            above: anchorWindow,
            autoDismissAfter: nil
        )
    }

    /// Update the text of the persistent recording-status card without
    /// rebuilding it. No-op if the card isn't currently visible.
    func updateRecordingStatusCard(text: String) {
        responseCard?.update(text: text)
    }

    /// Dismiss the persistent recording-status card. Called when the
    /// model reaches `.finished` or the user cancels recording.
    func hideRecordingStatusCard() {
        responseCard?.hide()
    }

    public func hide() {
        intendsToShow = false
        panel?.orderOut(nil)
        diagnosticLogger.info("PillOverlayPresenter.hide — panel=\(panel == nil ? "nil" : "exists")")
    }

    private func updatePanelPosition(_ panel: any PillOverlayPaneling) {
        let screenFrame = NSScreen.main?.visibleFrame ?? .zero
        let x = screenFrame.midX - panel.frame.width / 2
        let y = screenFrame.minY + 64

        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private var supportsTap: Bool {
        switch model.visibility {
        case .idle, .recording:
            return true
        case .hidden, .downloading, .loading, .transcribing, .done, .error:
            return false
        }
    }
}
