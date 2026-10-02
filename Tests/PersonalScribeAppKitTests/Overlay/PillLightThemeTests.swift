import AppKit
import SwiftUI
import XCTest
@testable import PersonalScribeAppKit

/// Light pill theme: the whole pill inverts (cream surface, dark ink).
/// Previously the surface was hardcoded navy while foreground tokens
/// switched to dark ink → dark-on-dark, logo invisible.
@MainActor
final class PillLightThemeTests: XCTestCase {
    func testPillSurfaceFollowsColorScheme() {
        XCTAssertEqual(
            PersonalScribeTheme.Pill.surface(for: .light),
            PersonalScribeTheme.Pill.Light.background
        )
        XCTAssertEqual(
            PersonalScribeTheme.Pill.surface(for: .dark),
            PersonalScribeTheme.Pill.Dark.background
        )
    }

    /// The live transcript card is its own panel; it must mirror the
    /// pill panel's resolved appearance so both invert together.
    func testStreamCardAdoptsPillWindowAppearanceWhenShown() {
        let pill = NSPanel(
            contentRect: NSRect(x: 100, y: 100, width: 280, height: 36),
            styleMask: [.borderless],
            backing: .buffered,
            defer: true
        )
        pill.appearance = NSAppearance(named: .aqua)
        let card = StreamCard()

        card.show(text: "hello", above: pill)

        XCTAssertEqual(card.appearance?.name, .aqua)
        card.hide()
    }
}
