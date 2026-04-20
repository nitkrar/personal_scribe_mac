import AppKit
import SwiftUI
import XCTest
@testable import PersonalScribeAppKit

/// Tests for `WindowTint` — the user-selectable main-window background
/// tint (Warm / Neutral / Dark). Reference:
/// `plans/App UI design/Claude_Final_Bundle_Prompt.md` §1 and the
/// `SeshatTheme.swift` drop-in (adopted verbatim, type/key names
/// adjusted per project naming rule — no "Seshat" prefix, no
/// "Ninimma" in code).
final class WindowTintTests: XCTestCase {
    // MARK: - Cases + UserDefaults round-trip

    func testCasesInclude_Warm_Neutral_Dark() {
        XCTAssertEqual(WindowTint.allCases, [.warm, .neutral, .dark])
    }

    func testDefaultResolvesToWarm() {
        let defaults = Self.isolatedDefaults()
        XCTAssertEqual(WindowTint.resolve(from: defaults), .warm)
    }

    func testResolveReadsPersistedDark() {
        let defaults = Self.isolatedDefaults()
        WindowTint.dark.persist(to: defaults)
        XCTAssertEqual(WindowTint.resolve(from: defaults), .dark)
    }

    func testResolveReadsPersistedNeutral() {
        let defaults = Self.isolatedDefaults()
        WindowTint.neutral.persist(to: defaults)
        XCTAssertEqual(WindowTint.resolve(from: defaults), .neutral)
    }

    func testResolveFallsBackToWarmOnInvalidValue() {
        let defaults = Self.isolatedDefaults()
        defaults.set("NotATint", forKey: WindowTint.userDefaultsKey)
        XCTAssertEqual(WindowTint.resolve(from: defaults), .warm)
    }

    func testPersistWritesRawValue() {
        let defaults = Self.isolatedDefaults()
        WindowTint.neutral.persist(to: defaults)
        XCTAssertEqual(
            defaults.string(forKey: WindowTint.userDefaultsKey),
            "Neutral"
        )
    }

    func testUserDefaultsKeyHasNoSeshatOrPersonalScribePrefix() {
        // Per project naming convention, UserDefaults keys are bundle-
        // scoped (`com.nitkrar.personal_scribe` domain already namespaces
        // them) so the key should be plain "WindowTint".
        XCTAssertEqual(WindowTint.userDefaultsKey, "WindowTint")
    }

    // MARK: - forcesDarkMode

    func testForcesDarkModeOnlyForDarkCase() {
        XCTAssertFalse(WindowTint.warm.forcesDarkMode)
        XCTAssertFalse(WindowTint.neutral.forcesDarkMode)
        XCTAssertTrue(WindowTint.dark.forcesDarkMode)
    }

    // MARK: - Semantic background hex specs (warm)

    func testWarmPrimaryBackgroundHex() {
        assertColor(WindowTint.warm.primaryBackground, equalsHex: "F5F5F0")
    }

    func testWarmSecondaryBackgroundHex() {
        assertColor(WindowTint.warm.secondaryBackground, equalsHex: "EBEBE6")
    }

    func testWarmCardBackgroundHex() {
        assertColor(WindowTint.warm.cardBackground, equalsHex: "FFFFFF")
    }

    func testWarmHoverBackgroundHex() {
        assertColor(WindowTint.warm.hoverBackground, equalsHex: "DCDCD7")
    }

    func testWarmPrimaryTextHex() {
        assertColor(WindowTint.warm.primaryText, equalsHex: "1C1C1E")
    }

    // MARK: - Semantic background hex specs (neutral)

    func testNeutralPrimaryBackgroundHex() {
        assertColor(WindowTint.neutral.primaryBackground, equalsHex: "F2F2F7")
    }

    func testNeutralSecondaryBackgroundHex() {
        assertColor(WindowTint.neutral.secondaryBackground, equalsHex: "E8E8ED")
    }

    func testNeutralCardBackgroundHex() {
        assertColor(WindowTint.neutral.cardBackground, equalsHex: "FFFFFF")
    }

    func testNeutralHoverBackgroundHex() {
        assertColor(WindowTint.neutral.hoverBackground, equalsHex: "DCDCE0")
    }

    func testNeutralPrimaryTextHex() {
        assertColor(WindowTint.neutral.primaryText, equalsHex: "1C1C1E")
    }

    // MARK: - Semantic background hex specs (dark)

    func testDarkPrimaryBackgroundHex() {
        assertColor(WindowTint.dark.primaryBackground, equalsHex: "0E0E14")
    }

    func testDarkSecondaryBackgroundHex() {
        assertColor(WindowTint.dark.secondaryBackground, equalsHex: "111318")
    }

    func testDarkCardBackgroundHex() {
        assertColor(WindowTint.dark.cardBackground, equalsHex: "1C1C1E")
    }

    func testDarkHoverBackgroundHex() {
        assertColor(WindowTint.dark.hoverBackground, equalsHex: "2A2A30")
    }

    func testDarkPrimaryTextHex() {
        assertColor(WindowTint.dark.primaryText, equalsHex: "F2F2F7")
    }

    // MARK: - Helpers

    private static func isolatedDefaults() -> UserDefaults {
        let suiteName = "WindowTintTests-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            fatalError("Could not create isolated UserDefaults for test")
        }
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private func assertColor(
        _ color: Color,
        equalsHex expected: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let expectedRGB = WindowTintTests.rgbTuple(fromHex: expected)
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
