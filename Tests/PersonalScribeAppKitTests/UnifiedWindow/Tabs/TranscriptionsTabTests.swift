import AppKit
import PersonalScribeCore
import SwiftUI
import XCTest
@testable import PersonalScribeAppKit

/// View-level tests for `TranscriptionsTab`. The main-body rendering is
/// exercised via `NSHostingController` instantiation smoke tests; the
/// observable contracts (e.g. `WindowTint.primaryBackground` being the
/// tab root's background — mockup-gap A.5) are driven through the pure
/// `resolvedBackground(windowTint:palette:)` helper so colour identity
/// can be asserted deterministically.
@MainActor
final class TranscriptionsTabTests: XCTestCase {
    // MARK: - mockup-gap A.5 — WindowTint primary background on tab root

    func testResolvedBackgroundPrefersWindowTintPrimaryBackgroundWhenPresent() {
        let palette = PersonalScribeTheme.Palette.light
        let resolvedWarm = TranscriptionsTab.resolvedBackground(
            windowTint: .warm,
            palette: palette
        )
        assertColor(resolvedWarm, equalsHex: "F5F5F0")

        let resolvedNeutral = TranscriptionsTab.resolvedBackground(
            windowTint: .neutral,
            palette: palette
        )
        assertColor(resolvedNeutral, equalsHex: "F2F2F7")
    }

    func testResolvedBackgroundFallsBackToPaletteAppBackgroundWhenTintNil() {
        // When no `WindowTint` has been injected into the environment
        // (e.g. unit-test host, preview without a `.windowTint()`
        // modifier), the tab root must fall back to the palette's
        // appBackground rather than inheriting from the ancestor.
        let palette = PersonalScribeTheme.Palette.light
        let resolved = TranscriptionsTab.resolvedBackground(
            windowTint: nil,
            palette: palette
        )
        // `Palette.light.appBackground` = #F5F5F0 (see
        // PersonalScribeTheme.swift:109).
        assertColor(resolved, equalsHex: "F5F5F0")
    }

    func testResolvedBackgroundFallsBackToDarkPaletteAppBackgroundWhenTintNil() {
        let palette = PersonalScribeTheme.Palette.dark
        let resolved = TranscriptionsTab.resolvedBackground(
            windowTint: nil,
            palette: palette
        )
        // `Palette.dark.appBackground` = #0E0E14 (see
        // PersonalScribeTheme.swift:86).
        assertColor(resolved, equalsHex: "0E0E14")
    }

    // MARK: - Smoke test: view instantiates

    func testTranscriptionsTabCanBeInstantiated() {
        let viewModel = TranscriptionsTabViewModel(
            reader: FakeEmptyReader()
        )
        let controller = NSHostingController(rootView: TranscriptionsTab(viewModel: viewModel))
        let view = controller.view
        view.layoutSubtreeIfNeeded()
        XCTAssertNotNil(view)
    }

    // MARK: - Colour-equality helper (copied from WindowTintTests to
    // keep this suite self-contained).

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

// MARK: - Inline fakes

/// Empty `TranscriptReading` double — just enough to satisfy the view
/// model's `load()` contract during smoke tests.
private actor FakeEmptyReader: TranscriptReading {
    func recent(limit: Int) async -> [TranscriptEntry] { [] }
    func search(query: String) async -> [TranscriptEntry] { [] }
    func all() async -> [TranscriptEntry] { [] }
    func mostRecentEntryWithAudio() async -> TranscriptEntry? { nil }
}
