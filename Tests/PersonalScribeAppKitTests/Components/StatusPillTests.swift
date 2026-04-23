import SwiftUI
import XCTest
@testable import PersonalScribeAppKit

/// Tests for `StatusPill`.
///
/// Scope rule (from PLAN_PHASES.md line 343): `StatusPill` is consumed by
/// `SettingsWindow` and `OnboardingWindow` ONLY. It is NOT used in the
/// menu bar (native NSMenu) or the pill overlay. We enforce this
/// architecturally by restricting what the component does — it carries
/// a colored dot + a label, nothing else.
final class StatusPillTests: XCTestCase {
    func testStatusColorForWarningUsesSystemOrange() {
        let dark = PersonalScribeTheme.Palette.dark
        XCTAssertEqual(
            StatusPill.Status.warning.color(for: dark),
            Color.orange
        )
    }

    func testStatusColorForFailedReusesStatusRecordingRed() {
        let light = PersonalScribeTheme.Palette.light
        XCTAssertEqual(
            StatusPill.Status.failed.color(for: light),
            light.statusRecording
        )
    }

    func testStatusColorForReadyUsesThemeStatusReady() {
        let dark = PersonalScribeTheme.Palette.dark
        XCTAssertEqual(
            StatusPill.Status.ready.color(for: dark),
            dark.statusReady
        )
    }

    func testStatusColorForRecordingUsesThemeStatusRecording() {
        let dark = PersonalScribeTheme.Palette.dark
        XCTAssertEqual(
            StatusPill.Status.recording.color(for: dark),
            dark.statusRecording
        )
    }

    func testStatusColorForNeutralUsesPaletteBrandChampagne() {
        let light = PersonalScribeTheme.Palette.light
        XCTAssertEqual(
            StatusPill.Status.neutral.color(for: light),
            light.brandChampagne
        )
    }
}
