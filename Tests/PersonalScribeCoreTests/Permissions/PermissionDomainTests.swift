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
}
