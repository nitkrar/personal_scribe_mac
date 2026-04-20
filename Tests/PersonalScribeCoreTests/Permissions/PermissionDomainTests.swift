import XCTest
@testable import PersonalScribeCore

final class PermissionDomainTests: XCTestCase {
    func testPermissionHasOnlyLockedCases() {
        XCTAssertEqual(
            Permission.allCases,
            [.microphone, .inputMonitoring, .accessibility]
        )
    }

    func testPermissionStatusHasOnlyPendingGrantedDenied() {
        XCTAssertEqual(
            PermissionStatus.allCases,
            [.pending, .granted, .denied]
        )
    }

    func testRequestOutcomeCarriesPromptOpenSettingsRelaunchAndFinalStatusFacts() {
        let outcome = RequestOutcome(
            prompted: true,
            openedSettings: false,
            requiresRelaunch: true,
            finalStatus: .pending
        )

        XCTAssertTrue(outcome.prompted)
        XCTAssertFalse(outcome.openedSettings)
        XCTAssertTrue(outcome.requiresRelaunch)
        XCTAssertEqual(outcome.finalStatus, .pending)
    }
}
