import SwiftUI
import XCTest
@testable import SeshatAppKit

/// Tests for `StatusPill`.
///
/// Scope rule (from PLAN_PHASES.md line 343): `StatusPill` is consumed by
/// `SettingsWindow` and `OnboardingWindow` ONLY. It is NOT used in the
/// menu bar (native NSMenu) or the pill overlay. We enforce this
/// architecturally by restricting what the component does — it carries
/// a colored dot + a label, nothing else.
final class StatusPillTests: XCTestCase {
    func testInitializerAcceptsStatusAndLabel() {
        let pill = StatusPill(status: .ready, label: "Ready to record")
        XCTAssertEqual(pill.status, .ready)
        XCTAssertEqual(pill.label, "Ready to record")
    }

    func testStatusEnumExposesReadyRecordingAndNeutral() {
        let all: Set<StatusPill.Status> = [.ready, .recording, .neutral]
        XCTAssertEqual(all.count, 3)
    }

    func testStatusColorForReadyUsesThemeStatusReady() {
        let dark = SeshatTheme.Palette.dark
        XCTAssertEqual(
            StatusPill.Status.ready.color(for: dark),
            dark.statusReady
        )
    }

    func testStatusColorForRecordingUsesThemeStatusRecording() {
        let dark = SeshatTheme.Palette.dark
        XCTAssertEqual(
            StatusPill.Status.recording.color(for: dark),
            dark.statusRecording
        )
    }

    func testStatusColorForNeutralUsesPaletteBrandChampagne() {
        let light = SeshatTheme.Palette.light
        XCTAssertEqual(
            StatusPill.Status.neutral.color(for: light),
            light.brandChampagne
        )
    }
}
