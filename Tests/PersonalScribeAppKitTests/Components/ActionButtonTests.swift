import AppKit
import SwiftUI
import XCTest
@testable import PersonalScribeAppKit

/// Tests for `ActionButton` — the champagne "Continue" / "Save" style.
@MainActor
final class ActionButtonTests: XCTestCase {
    func testInitializerAcceptsTitleAndAction() {
        var didFire = false
        let button = ActionButton(title: "Continue") { didFire = true }
        XCTAssertEqual(button.title, "Continue")
        XCTAssertFalse(didFire)
        button.action()
        XCTAssertTrue(didFire)
    }

    func testDefaultVariantIsPrimary() {
        let button = ActionButton(title: "Save") { }
        XCTAssertEqual(button.variant, .primary)
    }

    func testDefaultIsEnabled() {
        let button = ActionButton(title: "Save") { }
        XCTAssertTrue(button.isEnabled)
    }

    func testPrimaryVariantUsesChampagneFillAndDarkForeground() {
        let palette = PersonalScribeTheme.Palette.light

        assertColor(
            ActionButton.Variant.primary.backgroundColor(for: palette),
            equals: palette.brandChampagne
        )
        assertColor(
            ActionButton.Variant.primary.foregroundColor(for: palette),
            equals: PersonalScribeTheme.Palette.dark.appBackground
        )
        assertColor(
            ActionButton.Variant.primary.borderColor(for: palette),
            equals: palette.brandChampagne.opacity(
                PersonalScribeTheme.Components.ActionButton.primaryBorderOpacity
            )
        )
    }

    func testSecondaryVariantUsesSurfaceFillAndPrimaryText() {
        let palette = PersonalScribeTheme.Palette.dark

        assertColor(
            ActionButton.Variant.secondary.backgroundColor(for: palette),
            equals: palette.elevatedSurface
        )
        assertColor(
            ActionButton.Variant.secondary.foregroundColor(for: palette),
            equals: palette.primaryText
        )
        assertColor(
            ActionButton.Variant.secondary.borderColor(for: palette),
            equals: palette.brandChampagne.opacity(
                PersonalScribeTheme.Components.ActionButton.secondaryBorderOpacity
            )
        )
    }

    func testDisabledStateUsesThemeDisabledOpacity() {
        let button = ActionButton(title: "Save", isEnabled: false) { }
        XCTAssertEqual(
            button.effectiveOpacity,
            PersonalScribeTheme.Components.ActionButton.disabledOpacity,
            accuracy: 0.001
        )
    }

    func testEnabledStateKeepsFullOpacity() {
        let button = ActionButton(title: "Save") { }
        XCTAssertEqual(button.effectiveOpacity, 1.0, accuracy: 0.001)
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
