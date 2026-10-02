import AppKit
import SwiftUI
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

/// Pills grow away from a nearby edge: the edge-side stays fixed.
@MainActor
final class PillAnchorTests: XCTestCase {
    private let screen = NSRect(x: 0, y: 0, width: 1000, height: 800)
    private let largest = NSSize(width: 264, height: 36)
    private let idle = NSSize(width: 80, height: 28)
    private let recording = NSSize(width: 220, height: 36)

    private func anchor(_ home: NSRect) -> PillAnchor {
        PillAnchor(home: home, within: screen, largestSize: largest)
    }

    func testPillNearLeftEdgeKeepsItsLeftSide() {
        let home = NSRect(x: 8, y: 64, width: idle.width, height: idle.height)
        let grown = anchor(home).frame(for: recording, within: screen)
        XCTAssertEqual(grown.minX, home.minX)
        XCTAssertEqual(anchor(home).frame(for: idle, within: screen), home)
    }

    func testPillNearRightEdgeKeepsItsRightSide() {
        let home = NSRect(x: 912, y: 64, width: idle.width, height: idle.height)
        XCTAssertEqual(anchor(home).frame(for: recording, within: screen).maxX, home.maxX)
    }

    func testPillAwayFromEdgesGrowsFromItsCenter() {
        let home = NSRect(x: 460, y: 64, width: idle.width, height: idle.height)
        let grown = anchor(home).frame(for: recording, within: screen)
        XCTAssertEqual(grown.midX, home.midX)
        XCTAssertEqual(grown.minY, home.minY, "bottom edge stays fixed by default")
    }

    func testPillAtTopEdgeKeepsItsTopSide() {
        let home = NSRect(x: 460, y: 764, width: idle.width, height: idle.height)
        XCTAssertEqual(anchor(home).frame(for: recording, within: screen).maxY, home.maxY)
    }

    /// Pill content is pinned to the fixed side so it doesn't slide while
    /// the panel resizes around it.
    func testContentAlignsToTheFixedSide() {
        let left = NSRect(x: 8, y: 64, width: idle.width, height: idle.height)
        let topRight = NSRect(x: 912, y: 764, width: idle.width, height: idle.height)
        let middle = NSRect(x: 460, y: 64, width: idle.width, height: idle.height)
        XCTAssertEqual(anchor(left).contentAlignment, .bottomLeading)
        XCTAssertEqual(anchor(topRight).contentAlignment, .topTrailing)
        XCTAssertEqual(anchor(middle).contentAlignment, .bottom)
    }

    /// Dropped while wide (recording) near the left edge: the idle pill
    /// still hugs the left side instead of re-centering.
    func testAnchorFromWideDropKeepsEdgeForSmallerStates() {
        let home = NSRect(x: 8, y: 64, width: recording.width, height: recording.height)
        XCTAssertEqual(anchor(home).frame(for: idle, within: screen).minX, home.minX)
    }
}
