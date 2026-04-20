import AppKit
import SwiftUI
import XCTest
@testable import PersonalScribeAppKit

/// Tests for the `PersonalScribeTheme` design-system tokens.
///
/// These tests enforce the contract the Phase 2 plan binds us to:
///   * Both dark and light palettes MUST exist and be reachable from every
///     consumer via `PersonalScribeTheme.Palette.for(scheme:)`.
///   * Every hex value from
///     `plans/seshat_agent_bundle/01_Foundations/assets/colour_system.png`
///     MUST round-trip to the named semantic role.
///   * Typography, spacing, and corner-radius tokens MUST match the asset.
///
/// Hex values are compared via a reproducible helper (`rgbTuple`) because
/// `SwiftUI.Color` has no public equality that preserves channel values.
final class PersonalScribeThemeTests: XCTestCase {
    // MARK: - Palette presence

    func testDarkPaletteIsAccessible() {
        let palette = PersonalScribeTheme.Palette.for(scheme: .dark)
        XCTAssertEqual(palette.scheme, .dark)
    }

    func testLightPaletteIsAccessible() {
        let palette = PersonalScribeTheme.Palette.for(scheme: .light)
        XCTAssertEqual(palette.scheme, .light)
    }

    // MARK: - Dark palette hex spec

    func testDarkAppBackgroundHex() {
        assertColor(PersonalScribeTheme.Palette.dark.appBackground, equalsHex: "0E0E14")
    }

    func testDarkSurfaceHex() {
        assertColor(PersonalScribeTheme.Palette.dark.surface, equalsHex: "1C1C1E")
    }

    func testDarkElevatedSurfaceHex() {
        assertColor(PersonalScribeTheme.Palette.dark.elevatedSurface, equalsHex: "252525")
    }

    func testDarkHoverStateHex() {
        assertColor(PersonalScribeTheme.Palette.dark.hoverState, equalsHex: "2A2A2A")
    }

    func testDarkBrandChampagneHex() {
        assertColor(PersonalScribeTheme.Palette.dark.brandChampagne, equalsHex: "D4D0C8")
    }

    func testDarkPrimaryTextBase() {
        // Primary text in dark mode is #FFFFFF at 60% opacity per the asset.
        // We store the base as white and expose the opacity separately.
        assertColor(PersonalScribeTheme.Palette.dark.primaryTextBase, equalsHex: "FFFFFF")
        XCTAssertEqual(PersonalScribeTheme.Palette.dark.primaryTextOpacity, 0.60, accuracy: 0.001)
    }

    func testDarkSecondaryTextOpacity() {
        XCTAssertEqual(PersonalScribeTheme.Palette.dark.secondaryTextOpacity, 0.35, accuracy: 0.001)
    }

    func testDarkStatusReadyHex() {
        assertColor(PersonalScribeTheme.Palette.dark.statusReady, equalsHex: "30D158")
    }

    func testDarkStatusRecordingHex() {
        assertColor(PersonalScribeTheme.Palette.dark.statusRecording, equalsHex: "FF453A")
    }

    func testDarkStatusLinkHex() {
        assertColor(PersonalScribeTheme.Palette.dark.statusLink, equalsHex: "0A84FF")
    }

    // MARK: - Light palette hex spec

    func testLightAppBackgroundHex() {
        assertColor(PersonalScribeTheme.Palette.light.appBackground, equalsHex: "F5F5F0")
    }

    func testLightSurfaceHex() {
        assertColor(PersonalScribeTheme.Palette.light.surface, equalsHex: "FFFFFF")
    }

    func testLightElevatedSurfaceHex() {
        // Asset renders "#F0EFE9" (the OCR of the cell); we treat this as the
        // canonical pale-cream elevated surface for light mode.
        assertColor(PersonalScribeTheme.Palette.light.elevatedSurface, equalsHex: "F0EFE9")
    }

    func testLightHoverStateHex() {
        assertColor(PersonalScribeTheme.Palette.light.hoverState, equalsHex: "E8E7E0")
    }

    func testLightBrandChampagneDarkHex() {
        assertColor(PersonalScribeTheme.Palette.light.brandChampagne, equalsHex: "6B6760")
    }

    func testLightPrimaryTextHex() {
        // Light primary text is solid #1A1A1A at 100%.
        assertColor(PersonalScribeTheme.Palette.light.primaryTextBase, equalsHex: "1A1A1A")
        XCTAssertEqual(PersonalScribeTheme.Palette.light.primaryTextOpacity, 1.0, accuracy: 0.001)
    }

    func testLightSecondaryTextOpacity() {
        XCTAssertEqual(PersonalScribeTheme.Palette.light.secondaryTextOpacity, 0.45, accuracy: 0.001)
    }

    func testLightStatusReadyHex() {
        assertColor(PersonalScribeTheme.Palette.light.statusReady, equalsHex: "28A745")
    }

    func testLightStatusRecordingHex() {
        assertColor(PersonalScribeTheme.Palette.light.statusRecording, equalsHex: "D93025")
    }

    func testLightStatusLinkHex() {
        assertColor(PersonalScribeTheme.Palette.light.statusLink, equalsHex: "0066CC")
    }

    // MARK: - Typography tokens

    func testDisplayFontSizeIs20() {
        XCTAssertEqual(PersonalScribeTheme.Typography.display.pointSize, 20, accuracy: 0.01)
    }

    func testBodyFontSizeIs13() {
        XCTAssertEqual(PersonalScribeTheme.Typography.body.pointSize, 13, accuracy: 0.01)
    }

    func testCaptionFontSizeIs11() {
        XCTAssertEqual(PersonalScribeTheme.Typography.caption.pointSize, 11, accuracy: 0.01)
    }

    // MARK: - Spacing & radius tokens

    func testPillCornerRadiusIs12() {
        XCTAssertEqual(PersonalScribeTheme.Radius.pill, 12, accuracy: 0.001)
    }

    func testWindowCornerRadiusIs14() {
        XCTAssertEqual(PersonalScribeTheme.Radius.window, 14, accuracy: 0.001)
    }

    func testRowCornerRadiusIs8() {
        XCTAssertEqual(PersonalScribeTheme.Radius.row, 8, accuracy: 0.001)
    }

    func testWindowPaddingIs16() {
        XCTAssertEqual(PersonalScribeTheme.Spacing.windowPadding, 16, accuracy: 0.001)
    }

    func testRowPaddingIs12() {
        XCTAssertEqual(PersonalScribeTheme.Spacing.rowPadding, 12, accuracy: 0.001)
    }

    func testIconPaddingIs8() {
        XCTAssertEqual(PersonalScribeTheme.Spacing.iconPadding, 8, accuracy: 0.001)
    }

    // MARK: - Palette switching by ColorScheme

    func testPaletteForDarkSchemeReturnsDarkPalette() {
        let palette = PersonalScribeTheme.Palette.for(scheme: .dark)
        assertColor(palette.appBackground, equalsHex: "0E0E14")
    }

    func testPaletteForLightSchemeReturnsLightPalette() {
        let palette = PersonalScribeTheme.Palette.for(scheme: .light)
        assertColor(palette.appBackground, equalsHex: "F5F5F0")
    }

    // MARK: - Hex helper

    /// The theme-internal hex initializer is the ONLY place in the codebase
    /// allowed to parse hex strings. Verify it round-trips for a known value.
    func testColorHexInitializerRoundTrip() {
        let color = PersonalScribeTheme.color(hex: "D4D0C8")
        assertColor(color, equalsHex: "D4D0C8")
    }

    /// Malformed hex should fall back safely (clear / transparent) rather
    /// than trapping. Exact fallback choice is theme-internal; we assert
    /// only that it doesn't crash.
    func testColorHexInitializerRejectsMalformedStringWithoutCrashing() {
        _ = PersonalScribeTheme.color(hex: "NOTHEX")
    }

    // MARK: - v2 accent tokens

    func testAccentChampagneHex() {
        assertColor(PersonalScribeTheme.Accent.champagne, equalsHex: "CCB990")
    }

    func testAccentGoldHex() {
        assertColor(PersonalScribeTheme.Accent.gold, equalsHex: "B89961")
    }

    // MARK: - v2 status tokens

    func testStatusSuccessHex() {
        assertColor(PersonalScribeTheme.Status.success, equalsHex: "32C756")
    }

    func testStatusWarningHex() {
        assertColor(PersonalScribeTheme.Status.warning, equalsHex: "FF9E0A")
    }

    func testStatusErrorHex() {
        assertColor(PersonalScribeTheme.Status.error, equalsHex: "FF453A")
    }

    func testStatusLinkHex() {
        assertColor(PersonalScribeTheme.Status.link, equalsHex: "007AFF")
    }

    // MARK: - v2 separator tokens

    func testSeparatorPrimaryHex() {
        assertColor(PersonalScribeTheme.Separator.primary, equalsHex: "D1D1D6")
    }

    func testSeparatorSubtleHex() {
        assertColor(PersonalScribeTheme.Separator.subtle, equalsHex: "E5E5EA")
    }

    // MARK: - v2 pill explicit-appearance tokens

    func testPillDarkBackgroundHex() {
        assertColor(PersonalScribeTheme.Pill.Dark.background, equalsHex: "1A1B2E")
    }

    func testPillDarkWaveformHex() {
        assertColor(PersonalScribeTheme.Pill.Dark.waveform, equalsHex: "D4D0C8")
    }

    func testPillDarkStopHex() {
        assertColor(PersonalScribeTheme.Pill.Dark.stop, equalsHex: "F75138")
    }

    func testPillDarkCancelHex() {
        assertColor(PersonalScribeTheme.Pill.Dark.cancel, equalsHex: "99999E")
    }

    func testPillLightBackgroundHex() {
        assertColor(PersonalScribeTheme.Pill.Light.background, equalsHex: "F0EDE8")
    }

    func testPillLightWaveformHex() {
        assertColor(PersonalScribeTheme.Pill.Light.waveform, equalsHex: "333338")
    }

    func testPillLightStopHex() {
        assertColor(PersonalScribeTheme.Pill.Light.stop, equalsHex: "F75138")
    }

    func testPillLightCancelHex() {
        assertColor(PersonalScribeTheme.Pill.Light.cancel, equalsHex: "808082")
    }

    // MARK: - v2 extended typography tokens

    func testLargeTitleFontSizeIs26() {
        XCTAssertEqual(PersonalScribeTheme.Typography.largeTitle.pointSize, 26, accuracy: 0.01)
        XCTAssertEqual(PersonalScribeTheme.Typography.largeTitle.weight, .bold)
    }

    func testTitleFontSizeIs20Bold() {
        XCTAssertEqual(PersonalScribeTheme.Typography.title.pointSize, 20, accuracy: 0.01)
        XCTAssertEqual(PersonalScribeTheme.Typography.title.weight, .bold)
    }

    func testHeadlineFontSizeIs15Semibold() {
        XCTAssertEqual(PersonalScribeTheme.Typography.headline.pointSize, 15, accuracy: 0.01)
        XCTAssertEqual(PersonalScribeTheme.Typography.headline.weight, .semibold)
    }

    func testSectionLabelFontSizeIs11Semibold() {
        XCTAssertEqual(PersonalScribeTheme.Typography.sectionLabel.pointSize, 11, accuracy: 0.01)
        XCTAssertEqual(PersonalScribeTheme.Typography.sectionLabel.weight, .semibold)
    }

    func testCaptionBoldFontSizeIs11Semibold() {
        XCTAssertEqual(PersonalScribeTheme.Typography.captionBold.pointSize, 11, accuracy: 0.01)
        XCTAssertEqual(PersonalScribeTheme.Typography.captionBold.weight, .semibold)
    }

    // MARK: - v2 extended spacing tokens

    func testSpacingXsIs4() {
        XCTAssertEqual(PersonalScribeTheme.Spacing.xs, 4, accuracy: 0.001)
    }

    func testSpacingSmIs8() {
        XCTAssertEqual(PersonalScribeTheme.Spacing.sm, 8, accuracy: 0.001)
    }

    func testSpacingMdIs12() {
        XCTAssertEqual(PersonalScribeTheme.Spacing.md, 12, accuracy: 0.001)
    }

    func testSpacingLgIs16() {
        XCTAssertEqual(PersonalScribeTheme.Spacing.lg, 16, accuracy: 0.001)
    }

    func testSpacingXlIs24() {
        XCTAssertEqual(PersonalScribeTheme.Spacing.xl, 24, accuracy: 0.001)
    }

    func testSpacingXxlIs32() {
        XCTAssertEqual(PersonalScribeTheme.Spacing.xxl, 32, accuracy: 0.001)
    }

    // MARK: - v2 extended radius tokens

    func testRadiusSmIs6() {
        XCTAssertEqual(PersonalScribeTheme.Radius.sm, 6, accuracy: 0.001)
    }

    func testRadiusMdIs10() {
        XCTAssertEqual(PersonalScribeTheme.Radius.md, 10, accuracy: 0.001)
    }

    func testRadiusLgIs14() {
        XCTAssertEqual(PersonalScribeTheme.Radius.lg, 14, accuracy: 0.001)
    }

    func testRadiusCapsuleIs100() {
        XCTAssertEqual(PersonalScribeTheme.Radius.capsule, 100, accuracy: 0.001)
    }

    // MARK: - v2 row heights

    func testRowHeightCompactIs36() {
        XCTAssertEqual(PersonalScribeTheme.RowHeight.compact, 36, accuracy: 0.001)
    }

    func testRowHeightStandardIs52() {
        XCTAssertEqual(PersonalScribeTheme.RowHeight.standard, 52, accuracy: 0.001)
    }

    func testRowHeightTallIs56() {
        XCTAssertEqual(PersonalScribeTheme.RowHeight.tall, 56, accuracy: 0.001)
    }

    // MARK: - v2 layout constants

    func testLayoutSidebarWidthIs200() {
        XCTAssertEqual(PersonalScribeTheme.Layout.sidebarWidth, 200, accuracy: 0.001)
    }

    func testLayoutWindowMinWidthIs760() {
        XCTAssertEqual(PersonalScribeTheme.Layout.windowMinWidth, 760, accuracy: 0.001)
    }

    func testLayoutWindowMinHeightIs520() {
        XCTAssertEqual(PersonalScribeTheme.Layout.windowMinHeight, 520, accuracy: 0.001)
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
        let expectedRGB = PersonalScribeThemeTests.rgbTuple(fromHex: expected)
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
