import AppKit
import SwiftUI
import XCTest
@testable import PersonalScribeAppKit

/// Tests for `WindowTint` — the user-selectable main-window background
/// tint (Warm / Neutral). Reference:
/// `plans/App UI design/Claude_Final_Bundle_Prompt.md` §1 and the
/// `SeshatTheme.swift` drop-in (adopted verbatim, type/key names
/// adjusted per project naming rule — no "Seshat" prefix, no
/// "Ninimma" in code).
///
/// As of mockup-gaps G (2026-04-21) `WindowTint` no longer carries a
/// `.dark` case — app-level light/dark is owned by `AppTheme`. Legacy
/// persisted `"Dark"` raw values silently fall back to `.warm` via
/// the `resolve` unrecognised-raw-value path; that's the expected
/// zero-back-compat behaviour.
final class WindowTintTests: XCTestCase {
    // MARK: - Cases + UserDefaults round-trip

    func testCasesInclude_Warm_Neutral() {
        XCTAssertEqual(WindowTint.allCases, [.warm, .neutral])
    }

    func testDefaultResolvesToWarm() {
        let defaults = Self.isolatedDefaults()
        XCTAssertEqual(WindowTint.resolve(from: defaults), .warm)
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

    /// Legacy `"Dark"` raw value from pre-G persisted state must fall
    /// back to `.warm`, same as any other unrecognised value. There is
    /// no migration shim — this is the explicit zero-back-compat
    /// policy per mockup-gaps G.
    func testResolveFallsBackToWarmOnLegacyDarkRawValue() {
        let defaults = Self.isolatedDefaults()
        defaults.set("Dark", forKey: WindowTint.userDefaultsKey)
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
