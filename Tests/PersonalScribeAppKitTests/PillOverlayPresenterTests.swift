import AppKit
import SwiftUI
import XCTest
@testable import PersonalScribeAppKit

@MainActor
final class PillOverlayPresenterTests: XCTestCase {
    func testSmallMovementEndsAsClick() {
        var state = OverlayPanelInteractionState()

        state.begin(at: NSPoint(x: 10, y: 10))
        XCTAssertFalse(state.drag(to: NSPoint(x: 12, y: 12)))

        XCTAssertTrue(state.end(at: NSPoint(x: 12, y: 12)))
    }

    func testLargeMovementStartsDraggingAndSuppressesClick() {
        var state = OverlayPanelInteractionState()

        state.begin(at: NSPoint(x: 10, y: 10))

        XCTAssertTrue(state.drag(to: NSPoint(x: 20, y: 20)))
        XCTAssertTrue(state.isDragging)
        XCTAssertFalse(state.end(at: NSPoint(x: 20, y: 20)))
    }

    func testDraggingOnlyStartsOnce() {
        var state = OverlayPanelInteractionState()

        state.begin(at: NSPoint(x: 10, y: 10))

        XCTAssertTrue(state.drag(to: NSPoint(x: 20, y: 20)))
        XCTAssertFalse(state.drag(to: NSPoint(x: 30, y: 30)))
    }

    func testMouseUpFiresTapWhenTapIsEnabled() throws {
        let (window, hostingView) = makeHostingView()
        var tapCount = 0

        hostingView.onTap = {
            tapCount += 1
        }
        hostingView.isTapEnabled = { true }

        hostingView.mouseDown(with: try makeMouseEvent(.leftMouseDown, at: NSPoint(x: 20, y: 20), window: window))
        hostingView.mouseUp(with: try makeMouseEvent(.leftMouseUp, at: NSPoint(x: 20, y: 20), window: window))

        XCTAssertEqual(tapCount, 1)
    }

    func testMouseUpDoesNotFireTapWhenTapIsDisabled() throws {
        let (window, hostingView) = makeHostingView()
        var tapCount = 0

        hostingView.onTap = {
            tapCount += 1
        }
        hostingView.isTapEnabled = { false }

        hostingView.mouseDown(with: try makeMouseEvent(.leftMouseDown, at: NSPoint(x: 20, y: 20), window: window))
        hostingView.mouseUp(with: try makeMouseEvent(.leftMouseUp, at: NSPoint(x: 20, y: 20), window: window))

        XCTAssertEqual(tapCount, 0)
    }

    /// Test C — mouseDown -> drag past the 4pt threshold -> mouseUp must
    /// fire `onMouseDragged` and suppress `onTap`, even when tapping is
    /// otherwise enabled. Covers the hosting-view event path end-to-end
    /// (the state-machine-level assertion lives in
    /// `testLargeMovementStartsDraggingAndSuppressesClick`).
    func testDragPastThresholdSuppressesTapAndFiresDraggedCallback() throws {
        let (window, hostingView) = makeHostingView()
        var tapCount = 0
        var draggedCount = 0

        hostingView.onTap = { tapCount += 1 }
        hostingView.onMouseDragged = { draggedCount += 1 }
        hostingView.isTapEnabled = { true }

        hostingView.mouseDown(
            with: try makeMouseEvent(.leftMouseDown, at: NSPoint(x: 20, y: 20), window: window)
        )
        // First drag event crosses the 4pt threshold (hypot(8, 6) == 10).
        hostingView.mouseDragged(
            with: try makeMouseEvent(.leftMouseDragged, at: NSPoint(x: 28, y: 26), window: window)
        )
        // Second drag event inside an already-dragging session — must not
        // re-fire `onMouseDragged` (state machine only signals drag start once).
        hostingView.mouseDragged(
            with: try makeMouseEvent(.leftMouseDragged, at: NSPoint(x: 30, y: 30), window: window)
        )
        hostingView.mouseUp(
            with: try makeMouseEvent(.leftMouseUp, at: NSPoint(x: 30, y: 30), window: window)
        )

        XCTAssertEqual(draggedCount, 1, "onMouseDragged should fire once when drag first crosses threshold")
        XCTAssertEqual(tapCount, 0, "onTap must be suppressed after a drag session")
    }

    // MARK: - Sprint 2 Lane B1 — visibility-mode-aware presenter behaviour.

    /// If the view-model is already `.hidden` when the presenter
    /// subscribes, the presenter must not build or show a panel.
    func testPresenterDoesNotBuildPanelWhenCurrentVisibilityIsHidden() {
        let viewModel = PillOverlayViewModel(visibilityMode: .hidden)
        viewModel.apply(sessionState: .idle, preparationProgress: nil)
        let panelBuilder = RecordingPanelBuilder()

        let presenter = PillOverlayPresenter(
            model: viewModel,
            panelBuilder: panelBuilder
        )

        XCTAssertFalse(presenter.intendsToShow)
        XCTAssertEqual(panelBuilder.makePanelCallCount, 0)
    }

    /// `.alwaysOn` mode + idle session → presenter intends to show.
    func testPresenterShowsIdlePillInAlwaysOnMode() {
        let viewModel = PillOverlayViewModel(visibilityMode: .alwaysOn)
        viewModel.apply(sessionState: .idle, preparationProgress: nil)
        let panelBuilder = RecordingPanelBuilder()

        let presenter = PillOverlayPresenter(
            model: viewModel,
            panelBuilder: panelBuilder
        )

        XCTAssertTrue(presenter.intendsToShow,
                      "Always-on mode must intend to show the idle pill")
        XCTAssertEqual(panelBuilder.makePanelCallCount, 1)
        XCTAssertEqual(panelBuilder.panel.orderFrontCallCount, 1)
    }

    /// `.autoShow` mode + idle session → presenter does not intend to
    /// show.
    func testPresenterHidesIdlePillInAutoShowMode() {
        let viewModel = PillOverlayViewModel(visibilityMode: .autoShow)
        viewModel.apply(sessionState: .idle, preparationProgress: nil)
        let panelBuilder = RecordingPanelBuilder()

        let presenter = PillOverlayPresenter(
            model: viewModel,
            panelBuilder: panelBuilder
        )

        XCTAssertFalse(presenter.intendsToShow,
                       "Auto-show + idle session must not intend to present the pill")
        XCTAssertEqual(panelBuilder.makePanelCallCount, 0)
    }

    /// `.autoShow` mode + active recording → presenter intends to show.
    func testPresenterShowsRecordingPillInAutoShowMode() {
        let viewModel = PillOverlayViewModel(visibilityMode: .autoShow)
        viewModel.apply(sessionState: .recording, preparationProgress: nil)
        let panelBuilder = RecordingPanelBuilder()

        let presenter = PillOverlayPresenter(
            model: viewModel,
            panelBuilder: panelBuilder
        )

        XCTAssertTrue(presenter.intendsToShow,
                      "Auto-show + recording must intend to present the pill")
        XCTAssertEqual(panelBuilder.makePanelCallCount, 1)
        XCTAssertEqual(panelBuilder.panel.orderFrontCallCount, 1)
    }

    func testShowRecordingStatusCardUsesPersistentAutoDismiss() {
        let viewModel = PillOverlayViewModel(visibilityMode: .alwaysOn)
        viewModel.apply(sessionState: .recording, preparationProgress: nil)
        let panelBuilder = RecordingPanelBuilder()
        let responseCardBuilder = RecordingResponseCardBuilder()
        let presenter = PillOverlayPresenter(
            model: viewModel,
            panelBuilder: panelBuilder,
            responseCardBuilder: responseCardBuilder
        )

        presenter.showRecordingStatusCard(
            text: "Recording — transcribing when model is ready (10%)"
        )

        XCTAssertEqual(responseCardBuilder.makeResponseCardCallCount, 1)
        XCTAssertEqual(
            responseCardBuilder.card.lastText,
            "Recording — transcribing when model is ready (10%)"
        )
        XCTAssertNil(responseCardBuilder.card.lastAutoDismissAfter,
                     "recording-status card stays up until hideRecordingStatusCard()")
    }

    func testUpdateRecordingStatusCardReusesSameCardInstance() {
        let viewModel = PillOverlayViewModel(visibilityMode: .alwaysOn)
        viewModel.apply(sessionState: .recording, preparationProgress: nil)
        let panelBuilder = RecordingPanelBuilder()
        let responseCardBuilder = RecordingResponseCardBuilder()
        let presenter = PillOverlayPresenter(
            model: viewModel,
            panelBuilder: panelBuilder,
            responseCardBuilder: responseCardBuilder
        )

        presenter.showRecordingStatusCard(text: "Recording — transcribing when model is ready (10%)")
        presenter.updateRecordingStatusCard(text: "Recording — transcribing when model is ready (50%)")

        XCTAssertEqual(responseCardBuilder.makeResponseCardCallCount, 1,
                       "update must reuse the already-shown card")
        XCTAssertEqual(responseCardBuilder.card.updateCallCount, 1)
        XCTAssertEqual(
            responseCardBuilder.card.lastText,
            "Recording — transcribing when model is ready (50%)"
        )
    }

    func testResponseCardPersistentShowAndUpdatePreserveContract() {
        let card = RecordingResponseCard()
        let anchor = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 60),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        card.show(text: "Recording — transcribing when model is ready (10%)",
                  above: anchor,
                  autoDismissAfter: nil)
        XCTAssertEqual(card.showCallCount, 1)
        XCTAssertEqual(card.lastText, "Recording — transcribing when model is ready (10%)")
        XCTAssertNil(card.lastAutoDismissAfter,
                     "nil autoDismissAfter must persist; caller only calls hide() to dismiss")

        card.update(text: "Recording — transcribing when model is ready (50%)")
        XCTAssertEqual(card.updateCallCount, 1)
        XCTAssertEqual(card.lastText, "Recording — transcribing when model is ready (50%)")
        XCTAssertEqual(card.showCallCount, 1,
                       "update(text:) must not re-trigger show")
    }

    func testClipboardOnlyNoticeUsesResponseCardInfrastructure() {
        let viewModel = PillOverlayViewModel(visibilityMode: .alwaysOn)
        viewModel.apply(sessionState: .recording, preparationProgress: nil)
        let panelBuilder = RecordingPanelBuilder()
        let responseCardBuilder = RecordingResponseCardBuilder()
        let presenter = PillOverlayPresenter(
            model: viewModel,
            panelBuilder: panelBuilder,
            responseCardBuilder: responseCardBuilder
        )

        presenter.showClipboardOnlyNotice()

        XCTAssertEqual(responseCardBuilder.makeResponseCardCallCount, 1)
        XCTAssertEqual(
            responseCardBuilder.card.lastText,
            "Copied to clipboard · ⌘V to paste"
        )
        XCTAssertEqual(responseCardBuilder.card.lastAutoDismissAfter ?? .nan, 3.0, accuracy: 0.001)
        XCTAssertEqual(
            responseCardBuilder.card.lastAnchorWindow,
            panelBuilder.panel.anchorWindow
        )
    }

    // MARK: - Non-activating panel contract (Issue 6)
    //
    // The pill must not steal keyboard focus or promote the app to
    // frontmost when clicked. `.nonactivatingPanel` in the style mask
    // alone is insufficient when `canBecomeKey` is true — AppKit still
    // keys the panel on click, which steals focus from the prior app.
    // The full non-activating contract needs `canBecomeKey == false`
    // AND `canBecomeMain == false` on top of the style-mask bit.

    func testDraggablePanelCannotBecomeKey() {
        let panel = DraggablePanel(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 36),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        XCTAssertFalse(
            panel.canBecomeKey,
            "Pill panel must not become key — keying it steals keyboard focus from the prior app"
        )
    }

    func testDraggablePanelCannotBecomeMain() {
        let panel = DraggablePanel(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 36),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        XCTAssertFalse(
            panel.canBecomeMain,
            "Pill panel must not become main — main is reserved for the app's primary window"
        )
    }

    func testDraggablePanelStyleMaskRetainsNonactivating() {
        // Regression guard: a future refactor must not drop the
        // `.nonactivatingPanel` style bit from the pill panel. The bit
        // is what tells AppKit the click itself doesn't activate the
        // app; `canBecomeKey = false` handles the focus-theft edge,
        // but the style bit is still the first line of defence.
        let panel = DraggablePanel(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 36),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        XCTAssertTrue(panel.styleMask.contains(.nonactivatingPanel))
    }

    private func makeHostingView() -> (NSWindow, ClickThroughHostingView<EmptyView>) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 120, height: 80),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        let hostingView = ClickThroughHostingView(rootView: EmptyView())
        hostingView.frame = window.contentView?.bounds ?? .zero
        hostingView.autoresizingMask = [.width, .height]
        window.contentView?.addSubview(hostingView)
        return (window, hostingView)
    }

    private func makeMouseEvent(
        _ type: NSEvent.EventType,
        at point: NSPoint,
        window: NSWindow
    ) throws -> NSEvent {
        try XCTUnwrap(
            NSEvent.mouseEvent(
                with: type,
                location: point,
                modifierFlags: [],
                timestamp: 1,
                windowNumber: window.windowNumber,
                context: nil,
                eventNumber: 1,
                clickCount: 1,
                pressure: 1
            )
        )
    }
}

@MainActor
private final class RecordingPanelBuilder: PillOverlayPanelBuilding {
    let panel = RecordingPanel()
    private(set) var makePanelCallCount = 0

    func makePanel(
        model: PillOverlayViewModel,
        panelSize: NSSize,
        onTap: @escaping @MainActor () -> Void,
        onMouseDragged: @escaping @MainActor () -> Void,
        isTapEnabled: @escaping @MainActor () -> Bool
    ) -> any PillOverlayPaneling {
        makePanelCallCount += 1
        return panel
    }
}

@MainActor
private final class RecordingPanel: PillOverlayPaneling {
    var isVisible = false
    var frame = NSRect(x: 0, y: 0, width: 280, height: 60)
    let anchorWindow: NSWindow? = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 280, height: 60),
        styleMask: [.borderless],
        backing: .buffered,
        defer: false
    )
    private(set) var orderFrontCallCount = 0
    private(set) var orderOutCallCount = 0

    func orderFrontRegardless() {
        orderFrontCallCount += 1
        isVisible = true
    }

    func orderOut(_ sender: Any?) {
        orderOutCallCount += 1
        isVisible = false
    }

    func setFrameOrigin(_ point: NSPoint) {
        frame.origin = point
    }
}

@MainActor
private final class RecordingResponseCardBuilder: ResponseCardBuilding {
    let card = RecordingResponseCard()
    private(set) var makeResponseCardCallCount = 0

    func makeResponseCard() -> any ResponseCardPresenting {
        makeResponseCardCallCount += 1
        return card
    }
}

@MainActor
private final class RecordingResponseCard: ResponseCardPresenting {
    private(set) var lastText: String?
    private(set) var lastAnchorWindow: NSWindow?
    private(set) var lastAutoDismissAfter: TimeInterval?
    private(set) var showCallCount = 0
    private(set) var updateCallCount = 0

    func show(
        text: String,
        above pillWindow: NSWindow,
        autoDismissAfter: TimeInterval?
    ) {
        lastText = text
        lastAnchorWindow = pillWindow
        lastAutoDismissAfter = autoDismissAfter
        showCallCount += 1
    }

    func update(text: String) {
        lastText = text
        updateCallCount += 1
    }

    func hide() {}
}
