import SwiftUI
import XCTest
@testable import SeshatAppKit

/// Tests for `TagChip` — a small rounded chip used in the Notes
/// sidebar/editor for metadata tags.
final class TagChipTests: XCTestCase {
    func testInitializerAcceptsText() {
        let chip = TagChip(text: "meeting")
        XCTAssertEqual(chip.text, "meeting")
    }

    func testDefaultVariantIsNeutral() {
        let chip = TagChip(text: "meeting")
        XCTAssertEqual(chip.variant, .neutral)
    }

    func testExplicitVariantOverridesDefault() {
        let chip = TagChip(text: "meeting", variant: .accent)
        XCTAssertEqual(chip.variant, .accent)
    }

    func testVariantEnumCoversNeutralAndAccent() {
        let all: Set<TagChip.Variant> = [.neutral, .accent]
        XCTAssertEqual(all.count, 2)
    }
}
