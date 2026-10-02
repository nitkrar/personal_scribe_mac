import AppKit
import SwiftUI
import XCTest
@testable import PersonalScribeAppKit

/// Light pill theme uses a cream surface with dark foreground tokens.
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

    /// The live transcript card mirrors the pill panel's resolved appearance.
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
