import AppKit
import SwiftUI
import XCTest
@testable import SeshatAppKit

/// Tests for the `SeshatTheme` design-system tokens.
///
/// These tests enforce the contract the Phase 2 plan binds us to:
///   * Both dark and light palettes MUST exist and be reachable from every
///     consumer via `SeshatTheme.Palette.for(scheme:)`.
///   * Every hex value from
///     `plans/seshat_agent_bundle/01_Foundations/assets/colour_system.png`
///     MUST round-trip to the named semantic role.
///   * Typography, spacing, and corner-radius tokens MUST match the asset.
///
/// Hex values are compared via a reproducible helper (`rgbTuple`) because
/// `SwiftUI.Color` has no public equality that preserves channel values.
final class SeshatThemeTests: XCTestCase {
    // MARK: - Palette presence

    func testDarkPaletteIsAccessible() {
        let palette = SeshatTheme.Palette.for(scheme: .dark)
        XCTAssertEqual(palette.scheme, .dark)
    }

    func testLightPaletteIsAccessible() {
        let palette = SeshatTheme.Palette.for(scheme: .light)
        XCTAssertEqual(palette.scheme, .light)
    }

    // MARK: - Dark palette hex spec

    func testDarkAppBackgroundHex() {
        assertColor(SeshatTheme.Palette.dark.appBackground, equalsHex: "0E0E14")
    }

    func testDarkSurfaceHex() {
        assertColor(SeshatTheme.Palette.dark.surface, equalsHex: "1C1C1E")
    }

    func testDarkElevatedSurfaceHex() {
        assertColor(SeshatTheme.Palette.dark.elevatedSurface, equalsHex: "252525")
    }

    func testDarkHoverStateHex() {
        assertColor(SeshatTheme.Palette.dark.hoverState, equalsHex: "2A2A2A")
    }

    func testDarkBrandChampagneHex() {
        assertColor(SeshatTheme.Palette.dark.brandChampagne, equalsHex: "D4D0C8")
    }

    func testDarkPrimaryTextBase() {
        // Primary text in dark mode is #FFFFFF at 60% opacity per the asset.
        // We store the base as white and expose the opacity separately.
        assertColor(SeshatTheme.Palette.dark.primaryTextBase, equalsHex: "FFFFFF")
        XCTAssertEqual(SeshatTheme.Palette.dark.primaryTextOpacity, 0.60, accuracy: 0.001)
    }

    func testDarkSecondaryTextOpacity() {
        XCTAssertEqual(SeshatTheme.Palette.dark.secondaryTextOpacity, 0.35, accuracy: 0.001)
    }

    func testDarkStatusReadyHex() {
        assertColor(SeshatTheme.Palette.dark.statusReady, equalsHex: "30D158")
    }

    func testDarkStatusRecordingHex() {
        assertColor(SeshatTheme.Palette.dark.statusRecording, equalsHex: "FF453A")
    }

    func testDarkStatusLinkHex() {
        assertColor(SeshatTheme.Palette.dark.statusLink, equalsHex: "0A84FF")
    }

    // MARK: - Light palette hex spec

    func testLightAppBackgroundHex() {
        assertColor(SeshatTheme.Palette.light.appBackground, equalsHex: "F5F5F0")
    }

    func testLightSurfaceHex() {
        assertColor(SeshatTheme.Palette.light.surface, equalsHex: "FFFFFF")
    }

    func testLightElevatedSurfaceHex() {
        // Asset renders "#F0EFE9" (the OCR of the cell); we treat this as the
        // canonical pale-cream elevated surface for light mode.
        assertColor(SeshatTheme.Palette.light.elevatedSurface, equalsHex: "F0EFE9")
    }

    func testLightHoverStateHex() {
        assertColor(SeshatTheme.Palette.light.hoverState, equalsHex: "E8E7E0")
    }

    func testLightBrandChampagneDarkHex() {
        assertColor(SeshatTheme.Palette.light.brandChampagne, equalsHex: "6B6760")
    }

    func testLightPrimaryTextHex() {
        // Light primary text is solid #1A1A1A at 100%.
        assertColor(SeshatTheme.Palette.light.primaryTextBase, equalsHex: "1A1A1A")
        XCTAssertEqual(SeshatTheme.Palette.light.primaryTextOpacity, 1.0, accuracy: 0.001)
    }

    func testLightSecondaryTextOpacity() {
        XCTAssertEqual(SeshatTheme.Palette.light.secondaryTextOpacity, 0.45, accuracy: 0.001)
    }

    func testLightStatusReadyHex() {
        assertColor(SeshatTheme.Palette.light.statusReady, equalsHex: "28A745")
    }

    func testLightStatusRecordingHex() {
        assertColor(SeshatTheme.Palette.light.statusRecording, equalsHex: "D93025")
    }

    func testLightStatusLinkHex() {
        assertColor(SeshatTheme.Palette.light.statusLink, equalsHex: "0066CC")
    }

    // MARK: - Typography tokens

    func testDisplayFontSizeIs20() {
        XCTAssertEqual(SeshatTheme.Typography.display.pointSize, 20, accuracy: 0.01)
    }

    func testBodyFontSizeIs13() {
        XCTAssertEqual(SeshatTheme.Typography.body.pointSize, 13, accuracy: 0.01)
    }

    func testCaptionFontSizeIs11() {
        XCTAssertEqual(SeshatTheme.Typography.caption.pointSize, 11, accuracy: 0.01)
    }

    // MARK: - Spacing & radius tokens

    func testPillCornerRadiusIs12() {
        XCTAssertEqual(SeshatTheme.Radius.pill, 12, accuracy: 0.001)
    }

    func testWindowCornerRadiusIs14() {
        XCTAssertEqual(SeshatTheme.Radius.window, 14, accuracy: 0.001)
    }

    func testRowCornerRadiusIs8() {
        XCTAssertEqual(SeshatTheme.Radius.row, 8, accuracy: 0.001)
    }

    func testWindowPaddingIs16() {
        XCTAssertEqual(SeshatTheme.Spacing.windowPadding, 16, accuracy: 0.001)
    }

    func testRowPaddingIs12() {
        XCTAssertEqual(SeshatTheme.Spacing.rowPadding, 12, accuracy: 0.001)
    }

    func testIconPaddingIs8() {
        XCTAssertEqual(SeshatTheme.Spacing.iconPadding, 8, accuracy: 0.001)
    }

    // MARK: - Palette switching by ColorScheme

    func testPaletteForDarkSchemeReturnsDarkPalette() {
        let palette = SeshatTheme.Palette.for(scheme: .dark)
        assertColor(palette.appBackground, equalsHex: "0E0E14")
    }

    func testPaletteForLightSchemeReturnsLightPalette() {
        let palette = SeshatTheme.Palette.for(scheme: .light)
        assertColor(palette.appBackground, equalsHex: "F5F5F0")
    }

    // MARK: - Hex helper

    /// The theme-internal hex initializer is the ONLY place in the codebase
    /// allowed to parse hex strings. Verify it round-trips for a known value.
    func testColorHexInitializerRoundTrip() {
        let color = SeshatTheme.color(hex: "D4D0C8")
        assertColor(color, equalsHex: "D4D0C8")
    }

    /// Malformed hex should fall back safely (clear / transparent) rather
    /// than trapping. Exact fallback choice is theme-internal; we assert
    /// only that it doesn't crash.
    func testColorHexInitializerRejectsMalformedStringWithoutCrashing() {
        _ = SeshatTheme.color(hex: "NOTHEX")
    }

    // MARK: - Test helpers

    /// Compares a `Color` to a hex spec by extracting RGB from a platform
    /// `NSColor` (converted to sRGB). Uses a tight tolerance so we catch
    /// palette drift.
    private func assertColor(
        _ color: Color,
        equalsHex expected: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let expectedRGB = SeshatThemeTests.rgbTuple(fromHex: expected)
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
