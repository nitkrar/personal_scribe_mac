import SwiftUI
import XCTest
@testable import SeshatAppKit

/// Tests for the `ResponseCard` temporary-overlay component.
///
/// Reference: `plans/seshat_agent_bundle/03_Surfaces/PillOverlayWindow/command_mode_states.png`
/// PANEL 2 (Processing) + PANEL 3 (Query Response: Text Answer).
///
/// `ResponseCard` is the sliding card that appears above the pill when the
/// Command Mode surface returns a text answer or action confirmation. It is
/// stateless — the presenter owns visibility / auto-dismiss; the card only
/// renders the content it's asked to.
///
/// Scope for Sprint 2 (B1a): stub-level component — title + body + tint via
/// `SeshatTheme`. Action buttons (Copy / Open Note) and icons are a Phase 3
/// follow-up and explicitly out-of-scope here.
@MainActor
final class ResponseCardTests: XCTestCase {
    func testInitializerRetainsTitleAndBody() {
        let card = ResponseCard(
            title: "Q3 review",
            body: "Q3 review is Thursday at 3pm"
        )
        XCTAssertEqual(card.title, "Q3 review")
        XCTAssertEqual(card.body, "Q3 review is Thursday at 3pm")
    }

    func testInitializerAcceptsEmptyTitleAsNil() {
        // Some responses are body-only (action confirmations). The card
        // must accept an empty title without assuming a default.
        let card = ResponseCard(title: "", body: "Copied to clipboard")
        XCTAssertEqual(card.title, "")
        XCTAssertEqual(card.body, "Copied to clipboard")
    }

    func testAccessibilityLabelCombinesTitleAndBody() {
        let card = ResponseCard(
            title: "From your notes",
            body: "Q3 review is Thursday at 3pm"
        )
        XCTAssertEqual(
            card.accessibilityDescription,
            "From your notes. Q3 review is Thursday at 3pm"
        )
    }

    func testAccessibilityLabelOmitsTitleWhenEmpty() {
        let card = ResponseCard(title: "", body: "Copied to clipboard")
        XCTAssertEqual(card.accessibilityDescription, "Copied to clipboard")
    }
}
