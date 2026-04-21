import AppKit
import SwiftUI
import XCTest
@testable import PersonalScribeAppKit

/// #040 — the unified-window shell (sidebar background, detail backdrop,
/// brand-header / footer text, sidebar separator) was bound to
/// `WindowTint.*` which is a light-mode-only brand flavor. When
/// `AppTheme == .dark` flipped `\.colorScheme` to `.dark`, the tab
/// content correctly re-rendered dark but the shell stayed cream,
/// producing the "half light / half dark" look.
///
/// `UnifiedWindowChrome` is the scheme-aware helper extracted from
/// `UnifiedWindowView`. These tests lock the truth table:
///
/// * `.light, warm`    → windowTint flavor colors
/// * `.light, neutral` → windowTint flavor colors
/// * `.dark,  *`       → `PersonalScribeTheme.Palette.dark` tokens
///   (window tint is hidden in dark per G.4 — tint value is irrelevant)
final class UnifiedWindowChromeTests: XCTestCase {

    // MARK: - sidebarBackground

    func testSidebarBackgroundLightWarmUsesWarmTintSecondary() {
        assertColor(
            UnifiedWindowChrome.sidebarBackground(scheme: .light, tint: .warm),
            equalsHex: "EBEBE6"
        )
    }

    func testSidebarBackgroundLightNeutralUsesNeutralTintSecondary() {
        assertColor(
            UnifiedWindowChrome.sidebarBackground(scheme: .light, tint: .neutral),
            equalsHex: "E8E8ED"
        )
    }

    func testSidebarBackgroundDarkWarmUsesPaletteDarkSurface() {
        assertColor(
            UnifiedWindowChrome.sidebarBackground(scheme: .dark, tint: .warm),
            equalsHex: "1C1C1E"
        )
    }

    func testSidebarBackgroundDarkNeutralUsesPaletteDarkSurface() {
        assertColor(
            UnifiedWindowChrome.sidebarBackground(scheme: .dark, tint: .neutral),
            equalsHex: "1C1C1E"
        )
    }

    // MARK: - detailBackground

    func testDetailBackgroundLightWarmUsesWarmTintPrimary() {
        assertColor(
            UnifiedWindowChrome.detailBackground(scheme: .light, tint: .warm),
            equalsHex: "F5F5F0"
        )
    }

    func testDetailBackgroundLightNeutralUsesNeutralTintPrimary() {
        assertColor(
            UnifiedWindowChrome.detailBackground(scheme: .light, tint: .neutral),
            equalsHex: "F2F2F7"
        )
    }

    func testDetailBackgroundDarkWarmUsesPaletteDarkAppBackground() {
        assertColor(
            UnifiedWindowChrome.detailBackground(scheme: .dark, tint: .warm),
            equalsHex: "0E0E14"
        )
    }

    func testDetailBackgroundDarkNeutralUsesPaletteDarkAppBackground() {
        assertColor(
            UnifiedWindowChrome.detailBackground(scheme: .dark, tint: .neutral),
            equalsHex: "0E0E14"
        )
    }

    // MARK: - chromeText (base colour; callers apply their own opacity)

    func testChromeTextLightWarmUsesWarmTintPrimaryText() {
        assertColor(
            UnifiedWindowChrome.chromeText(scheme: .light, tint: .warm),
            equalsHex: "1C1C1E"
        )
    }

    func testChromeTextLightNeutralUsesNeutralTintPrimaryText() {
        assertColor(
            UnifiedWindowChrome.chromeText(scheme: .light, tint: .neutral),
            equalsHex: "1C1C1E"
        )
    }

    func testChromeTextDarkWarmUsesPaletteDarkPrimaryTextBase() {
        assertColor(
            UnifiedWindowChrome.chromeText(scheme: .dark, tint: .warm),
            equalsHex: "FFFFFF"
        )
    }

    func testChromeTextDarkNeutralUsesPaletteDarkPrimaryTextBase() {
        assertColor(
            UnifiedWindowChrome.chromeText(scheme: .dark, tint: .neutral),
            equalsHex: "FFFFFF"
        )
    }

    // MARK: - chromeSeparator (contract: chromeText at 8% alpha)

    func testChromeSeparatorLightMatchesChromeTextAt8PercentAlpha() {
        let separator = UnifiedWindowChrome.chromeSeparator(scheme: .light, tint: .warm)
        assertAlpha(separator, equals: 0.08)
        assertColor(separator, equalsHex: "1C1C1E")
    }

    func testChromeSeparatorDarkMatchesChromeTextAt8PercentAlpha() {
        let separator = UnifiedWindowChrome.chromeSeparator(scheme: .dark, tint: .warm)
        assertAlpha(separator, equals: 0.08)
        assertColor(separator, equalsHex: "FFFFFF")
    }

    // MARK: - helpers

    private func assertColor(
        _ color: Color,
        equalsHex expected: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let expectedRGB = Self.rgbTuple(fromHex: expected)
        guard let actual = NSColor(color).usingColorSpace(.sRGB) else {
            XCTFail("Could not convert Color to sRGB NSColor", file: file, line: line)
            return
        }
        let tolerance: CGFloat = 1.5 / 255.0
        XCTAssertEqual(
            Double(actual.redComponent),
            expectedRGB.r,
            accuracy: Double(tolerance),
            "red channel for #\(expected)",
            file: file,
            line: line
        )
        XCTAssertEqual(
            Double(actual.greenComponent),
            expectedRGB.g,
            accuracy: Double(tolerance),
            "green channel for #\(expected)",
            file: file,
            line: line
        )
        XCTAssertEqual(
            Double(actual.blueComponent),
            expectedRGB.b,
            accuracy: Double(tolerance),
            "blue channel for #\(expected)",
            file: file,
            line: line
        )
    }

    private func assertAlpha(
        _ color: Color,
        equals expected: Double,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let actual = NSColor(color).usingColorSpace(.sRGB) else {
            XCTFail("Could not convert Color to sRGB NSColor", file: file, line: line)
            return
        }
        XCTAssertEqual(
            Double(actual.alphaComponent),
            expected,
            accuracy: 0.005,
            "alpha channel",
            file: file,
            line: line
        )
    }

    private static func rgbTuple(fromHex hex: String) -> (r: Double, g: Double, b: Double) {
        let trimmed = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        var canonical = String(trimmed.prefix(6))
        while canonical.count < 6 { canonical += "0" }
        var value: UInt64 = 0
        Scanner(string: canonical).scanHexInt64(&value)
        let r = Double((value >> 16) & 0xFF) / 255.0
        let g = Double((value >> 8) & 0xFF) / 255.0
        let b = Double(value & 0xFF) / 255.0
        return (r, g, b)
    }
}
