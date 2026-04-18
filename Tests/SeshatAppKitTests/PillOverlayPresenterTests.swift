import AppKit
import SwiftUI
import XCTest
@testable import SeshatAppKit

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

    /// `.hidden` mode + recording session → presenter must not intend to
    /// show the panel. Lane B1 invariant: hidden overrides everything.
    ///
    /// Asserts on `intendsToShow` rather than NSPanel's real `isVisible`;
    /// real-visibility behaviour requires an AppKit runtime that headless
    /// XCTest doesn't fully emulate.
    func testPresenterDoesNotShowPanelWhenVisibilityIsHidden() {
        let viewModel = PillOverlayViewModel(visibilityMode: .hidden)
        let presenter = PillOverlayPresenter(model: viewModel)

        viewModel.apply(sessionState: .recording, preparationProgress: nil)

        // The `@Published` assign is synchronous; the presenter's Combine
        // sink fires on the current run-loop pass. Give it one spin.
        RunLoop.main.run(until: Date().addingTimeInterval(0.02))

        XCTAssertFalse(presenter.intendsToShow,
                       "Hidden visibility must not intend to show the panel")
    }

    /// `.alwaysOn` mode + idle session → presenter intends to show.
    func testPresenterShowsIdlePillInAlwaysOnMode() {
        let viewModel = PillOverlayViewModel(visibilityMode: .alwaysOn)
        let presenter = PillOverlayPresenter(model: viewModel)

        viewModel.apply(sessionState: .idle, preparationProgress: nil)
        RunLoop.main.run(until: Date().addingTimeInterval(0.02))

        XCTAssertTrue(presenter.intendsToShow,
                      "Always-on mode must intend to show the idle pill")
    }

    /// `.autoShow` mode + idle session → presenter does not intend to
    /// show.
    func testPresenterHidesIdlePillInAutoShowMode() {
        let viewModel = PillOverlayViewModel(visibilityMode: .autoShow)
        let presenter = PillOverlayPresenter(model: viewModel)

        viewModel.apply(sessionState: .idle, preparationProgress: nil)
        RunLoop.main.run(until: Date().addingTimeInterval(0.02))

        XCTAssertFalse(presenter.intendsToShow,
                       "Auto-show + idle session must not intend to present the pill")
    }

    /// `.autoShow` mode + active recording → presenter intends to show.
    func testPresenterShowsRecordingPillInAutoShowMode() {
        let viewModel = PillOverlayViewModel(visibilityMode: .autoShow)
        let presenter = PillOverlayPresenter(model: viewModel)

        viewModel.apply(sessionState: .recording, preparationProgress: nil)
        RunLoop.main.run(until: Date().addingTimeInterval(0.02))

        XCTAssertTrue(presenter.intendsToShow,
                      "Auto-show + recording must intend to present the pill")
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
