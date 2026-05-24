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

    // `.nonactivatingPanel` in the style mask tells AppKit not to
    // activate the app when the panel is clicked, but by itself it does
    // not prevent the panel from being keyed — a non-activating panel
    // that returns `canBecomeKey = true` can still steal keyboard focus
    // from the previously-frontmost app without a visible activation
    // flash. That is exactly the Issue 6 symptom: click the pill to
    // stop a recording, the user's real focus target (Slack, VS Code)
    // silently loses focus, and `NSWorkspace.frontmostApplication`
    // briefly returns Ninimma — breaking the auto-paste target-resolution
    // path until the AX probe in ClipboardBatchOutput catches it.
    //
    // The fix is the full non-activating contract: style-mask bit +
    // `canBecomeKey = false` + `canBecomeMain = false`. Matches the
    // Wispr Flow pattern (Electron: `focusable: false` on a panel-type
    // BrowserWindow). There is no keyboard input inside the pill and
    // no @FocusState consumers, so dropping key status does not
    // regress any existing interaction — clicks still land in
    // `ClickThroughHostingView.mouseUp` via the `acceptsFirstMouse`
    // override.
    override var canBecomeKey: Bool {
        false
    }

    override var canBecomeMain: Bool {
        false
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
            MainActor.assumeIsolated {
                self?.applyResolvedAppearance()
            }
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
    /// Resize + reposition the panel atomically. `animate: true` routes
    /// to AppKit's `NSPanel.setFrame(_:display:animate:)` spring, which
    /// owns the per-state panel frame tween (#044). `animate: false` is
    /// used on the initial show from `.hidden` so the panel arrives
    /// already at the target state's footprint instead of morphing out
    /// of the stale default.
    func setFrame(_ frame: NSRect, animate: Bool)
}

extension PillOverlayPaneling {
    var anchorWindow: NSWindow? { nil }
}

extension DraggablePanel: PillOverlayPaneling {
    var anchorWindow: NSWindow? { self }

    func setFrame(_ frame: NSRect, animate: Bool) {
        setFrame(frame, display: true, animate: animate)
    }
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
    private let streamCardBuilder: any StreamCardBuilding
    private var panel: (any PillOverlayPaneling)?
    private var responseCard: (any ResponseCardPresenting)?
    private var streamCard: (any StreamCardPresenting)?
    private var visibilityCancellable: AnyCancellable?
    private let diagnosticLogger: PersonalScribeLogger
    private static let clipboardOnlyNoticeText = "Copied to clipboard · ⌘V to paste"
    private static let clipboardOnlyNoticeDismissAfter: TimeInterval = 3.0

    /// Whether the presenter last asked the panel to show itself. Exposed
    /// for tests — NSPanel's real `isVisible` depends on AppKit runtime
    /// state that isn't reliable in unit tests.
    public private(set) var intendsToShow: Bool = false
    /// Fallback panel canvas size used ONLY when the view-model's
    /// current visibility is `.hidden` (e.g. first construction before
    /// any visibility push). Pre-#044 this was the single canonical
    /// panel footprint and created the invisible click-halo bug; it is
    /// now superseded by per-state sizing driven through
    /// `PillOverlayView.size(for:)` on every visibility transition.
    private let panelSize = NSSize(width: 280, height: 60)
    private var hasUserRepositioned = false
    /// The last visibility we sized the panel for. Used to decide
    /// whether `animate: true` should be passed to `setFrame` — the
    /// first transition out of `.hidden` must arrive at the target
    /// size with NO animation (panel is being shown for the first
    /// time), and pill↔cancel transitions are crossfaded by SwiftUI so
    /// the frame update itself is not animated.
    private var lastSizedVisibility: PillOverlayViewModel.Visibility?
    private var lastLoggedVisibilitySinkState: VisibilitySinkLogState?

    public convenience init(
        model: PillOverlayViewModel,
        onTap: @escaping @MainActor () -> Void = {},
        diagnosticLogger: PersonalScribeLogger
    ) {
        self.init(
            model: model,
            onTap: onTap,
            panelBuilder: AppKitPillOverlayPanelBuilder(),
            responseCardBuilder: LiveResponseCardBuilder(),
            streamCardBuilder: LiveStreamCardBuilder(),
            diagnosticLogger: diagnosticLogger
        )
    }

    init(
        model: PillOverlayViewModel,
        onTap: @escaping @MainActor () -> Void = {},
        panelBuilder: any PillOverlayPanelBuilding,
        responseCardBuilder: any ResponseCardBuilding = LiveResponseCardBuilder(),
        streamCardBuilder: any StreamCardBuilding = LiveStreamCardBuilder(),
        diagnosticLogger: PersonalScribeLogger = PersonalScribeLogger.testing(
            category: PersonalScribeLogCategory.ui
        )
    ) {
        self.model = model
        self.onTap = onTap
        self.panelBuilder = panelBuilder
        self.responseCardBuilder = responseCardBuilder
        self.streamCardBuilder = streamCardBuilder
        self.diagnosticLogger = diagnosticLogger
        visibilityCancellable = model.$visibility.sink { [weak self] visibility in
            guard let self else {
                return
            }

            switch visibility {
            case .hidden:
                hide()
            case .cancelled,
                 .idle, .downloading, .loading,
                 .holdToRecord, .recording, .transcribing, .done, .error:
                // #044: panel must be sized per visibility so the panel
                // frame == visible pill frame (no invisible click-halo).
                // First show from `.hidden`: `show()` pre-sizes the
                // panel to the target state's footprint BEFORE
                // `orderFrontRegardless`, so the panel appears already
                // at the right size (no default-280×60 flash). Later
                // transitions call `applyVisibilityResize`, which
                // animates the frame via
                // `NSPanel.setFrame(_:display:animate:)`.
                if isVisible {
                    applyVisibilityResize(to: visibility)
                } else {
                    show(initialVisibility: visibility)
                }
            }

            logVisibilitySinkIfNeeded(for: visibility)
        }
    }

    private struct VisibilitySinkLogState: Equatable {
        let visibility: PillOverlayViewModel.Visibility
        let isVisible: Bool
    }

    private func logVisibilitySinkIfNeeded(for visibility: PillOverlayViewModel.Visibility) {
        let state = VisibilitySinkLogState(
            visibility: visibility,
            isVisible: isVisible
        )
        guard state != lastLoggedVisibilitySinkState else {
            return
        }

        lastLoggedVisibilitySinkState = state
        diagnosticLogger.info(
            "PillOverlayPresenter visibility-sink — visibility=\(visibility) isVisible=\(state.isVisible)"
        )
    }

    /// Core #044 resize logic. Given the new visibility, compute the
    /// target panel footprint and reposition to preserve the visible
    /// pill's bottom-center. Animation is driven by
    /// `NSPanel.setFrame(_:display:animate:)` for pill↔pill morphs and
    /// suppressed for pill↔CancelCard crossfades (SwiftUI owns that
    /// fade via the `.animation(_, value:isCancelled)` in
    /// `PillOverlayView`).
    private func applyVisibilityResize(to visibility: PillOverlayViewModel.Visibility) {
        guard let panel else {
            return
        }

        let newSize = PillOverlayView.size(for: visibility)
        guard newSize != .zero else {
            // `.hidden` is routed to `hide()` already — defensive no-op.
            return
        }

        // Bottom-center anchor: preserve the x-midpoint and bottom-Y of
        // the currently-visible pill so the user's reading point stays
        // fixed across state morphs. For first-show the default
        // `updatePanelPosition` has already centered the panel at
        // screen.midX / screen.minY + 64; for subsequent transitions
        // the panel's own frame carries the (possibly user-dragged)
        // anchor forward.
        let previousFrame = panel.frame
        let newOrigin = NSPoint(
            x: previousFrame.midX - newSize.width / 2,
            y: previousFrame.minY
        )
        let newFrame = NSRect(origin: newOrigin, size: newSize)

        // Animation policy:
        // - first sizing after show (`lastSizedVisibility == nil`): no
        //   animate — panel arrives already at target size.
        // - pill↔cancel transitions: no animate — SwiftUI crossfades
        //   the content; the panel just jumps to the cancel footprint.
        // - pill↔pill transitions: animate — AppKit tweens the frame.
        let isFirstSizing = (lastSizedVisibility == nil)
        let wasCancelled = (lastSizedVisibility == .cancelled)
        let becomingCancelled = (visibility == .cancelled)
        let involvesCancelCrossfade = wasCancelled || becomingCancelled
        let shouldAnimate = !isFirstSizing && !involvesCancelCrossfade

        panel.setFrame(newFrame, animate: shouldAnimate)
        lastSizedVisibility = visibility

        // Response card follows the pill's bottom-center. A SwiftUI
        // `.animation` on the card itself is not viable (NSPanel-based),
        // so reanchor on every pill resize where the card is visible.
        reanchorResponseCard(pillFrame: newFrame)
        reanchorStreamCard(pillFrame: newFrame)
    }

    public var isVisible: Bool {
        panel?.isVisible == true
    }

    public func show() {
        show(initialVisibility: nil)
    }

    /// Internal overload used by the visibility sink to hand the
    /// presenter the target state at the moment of first show. #044:
    /// when `initialVisibility` is non-nil, the panel is sized to the
    /// matching pill footprint BEFORE `orderFrontRegardless`, so the
    /// panel appears already at the correct state size instead of
    /// flashing at the default 280×60 canvas.
    private func show(initialVisibility: PillOverlayViewModel.Visibility?) {
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

        // #044: pre-size the panel to the target state's footprint
        // before ordering it front so the very first frame shown is
        // already at the correct size.
        if let initialVisibility {
            applyVisibilityResize(to: initialVisibility)
        }

        panel.orderFrontRegardless()
        diagnosticLogger.info("PillOverlayPresenter.show — panelExisted=\(panelExisted) frame=\(panel.frame) isVisible=\(panel.isVisible)")
    }

    private func reanchorResponseCard(pillFrame: NSRect) {
        responseCard?.reanchor(abovePillFrame: pillFrame)
    }

    private func reanchorStreamCard(pillFrame: NSRect) {
        streamCard?.reanchor(abovePillFrame: pillFrame)
    }

    func showClipboardOnlyNotice() {
        guard let anchorWindow = panel?.anchorWindow else {
            diagnosticLogger.info("PillOverlayPresenter.showClipboardOnlyNotice — skipped because no anchor window is available")
            return
        }

        hideStreamCard()
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
        showRecordingStatusCard(
            text: text,
            link: nil,
            autoDismissAfter: nil,
            onLinkTap: nil
        )
    }

    /// Stage B (#046) overload: supports an optional link region and an
    /// explicit auto-dismiss. Used for the "Auto stopped. Update
    /// settings to change." notification (2.0s auto-dismiss + link) and
    /// the "…stopping, speak to continue" warning (no link, no
    /// auto-dismiss — dismissed when grace resolves).
    func showRecordingStatusCard(
        text: String,
        link: StatusCardLink?,
        autoDismissAfter: TimeInterval?,
        onLinkTap: (@Sendable @MainActor (StatusCardLinkAction) -> Void)?
    ) {
        guard let anchorWindow = panel?.anchorWindow else {
            diagnosticLogger.info("PillOverlayPresenter.showRecordingStatusCard — skipped because no anchor window is available")
            return
        }

        hideStreamCard()
        let responseCard = responseCard ?? responseCardBuilder.makeResponseCard()
        self.responseCard = responseCard
        responseCard.show(
            text: text,
            link: link,
            above: anchorWindow,
            autoDismissAfter: autoDismissAfter,
            onLinkTap: onLinkTap
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

    func showStreamCard(text: String) {
        guard let anchorWindow = panel?.anchorWindow else {
            diagnosticLogger.info("PillOverlayPresenter.showStreamCard — skipped because no anchor window is available")
            return
        }

        let streamCard = streamCard ?? streamCardBuilder.makeStreamCard()
        self.streamCard = streamCard
        streamCard.show(text: text, above: anchorWindow)
    }

    func updateStreamCard(text: String) {
        guard let streamCard else {
            showStreamCard(text: text)
            return
        }

        streamCard.update(text: text)
    }

    func hideStreamCard() {
        streamCard?.hide()
    }

    func logStreamCardShown(
        textLength: Int,
        sessionState: SessionState,
        isStreamingSession: Bool
    ) {
        diagnosticLogger.info(
            "stream_card_shown — initialTextLength=\(textLength) sessionState=\(sessionState) isStreamingSession=\(isStreamingSession)"
        )
    }

    func logStreamCardHidden(
        reason: String,
        updatesSinceShow: Int,
        finalTextLength: Int,
        maxTextLength: Int,
        sessionState: SessionState,
        isStreamingSession: Bool
    ) {
        diagnosticLogger.info(
            "stream_card_hidden — reason=\(reason) updatesSinceShow=\(updatesSinceShow) finalTextLength=\(finalTextLength) maxTextLength=\(maxTextLength) sessionState=\(sessionState) isStreamingSession=\(isStreamingSession)"
        )
    }

    public func hide() {
        intendsToShow = false
        panel?.orderOut(nil)
        hideStreamCard()
        // Clear the "last sized" flag so the next transition out of
        // `.hidden` performs a non-animated initial size (panel arrives
        // already at the target footprint instead of morphing from the
        // stale prior state). Matches the first-show contract in
        // `applyVisibilityResize`.
        lastSizedVisibility = nil
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
        // `.holdToRecord` is driven by the modifier key rather than the
        // pill click target, so taps are NOT enabled during hold —
        // otherwise a click mid-hold would fight the release-to-
        // transcribe semantic.
        case .idle, .recording:
            return true
        case .hidden, .downloading, .loading, .holdToRecord, .transcribing, .done, .cancelled, .error:
            return false
        }
    }
}
