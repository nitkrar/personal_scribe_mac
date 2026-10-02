import AppKit
import XCTest
@testable import PersonalScribeAppKit

@MainActor
final class OverlayPlacementTests: XCTestCase {
    private let screen = NSRect(x: 0, y: 0, width: 1000, height: 800)

    func testPillPastLeftEdgeIsPulledOnScreen() {
        let frame = NSRect(x: -60, y: 100, width: 220, height: 44)
        let placed = OverlayPlacement.clamp(frame, within: screen)
        XCTAssertEqual(placed.minX, screen.minX + OverlayPlacement.screenMargin)
        XCTAssertEqual(placed.minY, 100)
        XCTAssertEqual(placed.size, frame.size)
    }

    func testPillPastRightEdgeIsPulledOnScreen() {
        let frame = NSRect(x: 900, y: 100, width: 220, height: 44)
        let placed = OverlayPlacement.clamp(frame, within: screen)
        XCTAssertEqual(placed.maxX, screen.maxX - OverlayPlacement.screenMargin)
    }

    func testPillPastTopAndBottomIsPulledOnScreen() {
        let top = OverlayPlacement.clamp(NSRect(x: 100, y: 790, width: 220, height: 44), within: screen)
        XCTAssertEqual(top.maxY, screen.maxY - OverlayPlacement.screenMargin)
        let bottom = OverlayPlacement.clamp(NSRect(x: 100, y: -20, width: 220, height: 44), within: screen)
        XCTAssertEqual(bottom.minY, screen.minY + OverlayPlacement.screenMargin)
    }

    func testOnScreenPillIsUntouched() {
        let frame = NSRect(x: 300, y: 100, width: 220, height: 44)
        XCTAssertEqual(OverlayPlacement.clamp(frame, within: screen), frame)
    }

    func testCardSitsCenteredAbovePillWhenThereIsRoom() {
        let pill = NSRect(x: 390, y: 64, width: 220, height: 44)
        let card = OverlayPlacement.cardFrame(
            size: NSSize(width: 320, height: 42), pillFrame: pill, within: screen, gap: 8
        )
        XCTAssertEqual(card.midX, pill.midX)
        XCTAssertEqual(card.minY, pill.maxY + 8)
    }

    func testCardNearLeftEdgeStaysOnScreen() {
        let pill = NSRect(x: 8, y: 64, width: 220, height: 44)
        let card = OverlayPlacement.cardFrame(
            size: NSSize(width: 400, height: 42), pillFrame: pill, within: screen, gap: 8
        )
        XCTAssertEqual(card.minX, screen.minX + OverlayPlacement.screenMargin)
    }

    func testCardNearRightEdgeStaysOnScreen() {
        let pill = NSRect(x: 772, y: 64, width: 220, height: 44)
        let card = OverlayPlacement.cardFrame(
            size: NSSize(width: 400, height: 42), pillFrame: pill, within: screen, gap: 8
        )
        XCTAssertEqual(card.maxX, screen.maxX - OverlayPlacement.screenMargin)
    }

    func testCardFlipsBelowPillAtTopEdge() {
        let pill = NSRect(x: 390, y: 748, width: 220, height: 44)
        let card = OverlayPlacement.cardFrame(
            size: NSSize(width: 320, height: 42), pillFrame: pill, within: screen, gap: 8
        )
        XCTAssertEqual(card.maxY, pill.minY - 8)
        XCTAssertFalse(card.intersects(pill))
    }

    func testCardWiderThanScreenIsCappedToScreenWidth() {
        let narrow = NSRect(x: 0, y: 0, width: 300, height: 800)
        let pill = NSRect(x: 40, y: 64, width: 220, height: 44)
        let card = OverlayPlacement.cardFrame(
            size: NSSize(width: 560, height: 42), pillFrame: pill, within: narrow, gap: 8
        )
        XCTAssertGreaterThanOrEqual(card.minX, narrow.minX)
        XCTAssertLessThanOrEqual(card.maxX, narrow.maxX)
    }
}
