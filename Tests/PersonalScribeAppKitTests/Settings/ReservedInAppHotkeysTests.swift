import AppKit
import XCTest
@testable import PersonalScribeAppKit
import PersonalScribeCore

@MainActor
final class ReservedInAppHotkeysTests: XCTestCase {

    /// H.7 (#089) — pins the `additionalReservations` parameter on
    /// `reservationReason(for:additionalReservations:)`. A refactor
    /// that drops the param consultation would silently break
    /// per-mode hotkey collision detection (L-23).
    func testReservationReasonRejectsCollidingPerModeHotkey() {
        let candidate = HotkeyPreference(
            keyCode: 9, // V
            tapCount: 1,
            modifiers: NSEvent.ModifierFlags([.command, .option]).rawValue
        )

        // Without the candidate in `additionalReservations`, the chord
        // is free.
        XCTAssertNil(
            ReservedInAppHotkeys.reservationReason(for: candidate),
            "Cmd+Opt+V is not a built-in reservation; unguarded recorder must accept it"
        )

        // With the same chord listed as another mode's hotkey, the
        // recorder must surface a reservation reason.
        let reason = ReservedInAppHotkeys.reservationReason(
            for: candidate,
            additionalReservations: [candidate]
        )
        XCTAssertNotNil(
            reason,
            "Per-mode collision must surface a reservation reason"
        )
    }
}
