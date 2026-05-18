import AppKit
import SwiftUI
import XCTest
@testable import PersonalScribeAppKit

/// Tests for `TagChip` — a small rounded chip used in the Notes
/// sidebar/editor for metadata tags.
@MainActor
final class TagChipTests: XCTestCase {
    func testDefaultVariantIsNeutral() {
        let chip = TagChip(text: "meeting")
        XCTAssertEqual(chip.variant, .neutral)
    }

    func testNeutralVariantUsesElevatedSurfaceStyling() {
        let palette = PersonalScribeTheme.Palette.dark

        assertColor(
            TagChip.Variant.neutral.foregroundColor(for: palette),
            equals: palette.primaryText
        )
        assertColor(
            TagChip.Variant.neutral.backgroundColor(for: palette),
            equals: palette.elevatedSurface
        )
        assertColor(
            TagChip.Variant.neutral.borderColor(for: palette),
            equals: palette.brandChampagne.opacity(
                PersonalScribeTheme.Components.TagChip.neutralBorderOpacity
            )
        )
    }

    func testAccentVariantUsesChampagneStyling() {
        let palette = PersonalScribeTheme.Palette.light

        assertColor(
            TagChip.Variant.accent.foregroundColor(for: palette),
            equals: palette.brandChampagne
        )
        assertColor(
            TagChip.Variant.accent.backgroundColor(for: palette),
            equals: palette.brandChampagne.opacity(
                PersonalScribeTheme.Components.TagChip.accentFillOpacity
            )
        )
        assertColor(
            TagChip.Variant.accent.borderColor(for: palette),
            equals: palette.brandChampagne.opacity(
                PersonalScribeTheme.Components.TagChip.accentBorderOpacity
            )
        )
    }

    private func assertColor(
        _ color: Color,
        equals expected: Color,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let actual = NSColor(color).usingColorSpace(.sRGB),
              let expected = NSColor(expected).usingColorSpace(.sRGB)
        else {
            XCTFail("Could not convert Color to sRGB NSColor", file: file, line: line)
            return
        }

        let tolerance: CGFloat = 1.5 / 255.0
        XCTAssertEqual(
            Double(actual.redComponent),
            Double(expected.redComponent),
            accuracy: Double(tolerance),
            file: file,
            line: line
        )
        XCTAssertEqual(
            Double(actual.greenComponent),
            Double(expected.greenComponent),
            accuracy: Double(tolerance),
            file: file,
            line: line
        )
        XCTAssertEqual(
            Double(actual.blueComponent),
            Double(expected.blueComponent),
            accuracy: Double(tolerance),
            file: file,
            line: line
        )
        XCTAssertEqual(
            Double(actual.alphaComponent),
            Double(expected.alphaComponent),
            accuracy: Double(tolerance),
            file: file,
            line: line
        )
    }
}
