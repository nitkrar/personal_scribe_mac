import XCTest
@testable import SeshatCore

final class SessionStateTests: XCTestCase {
    func testErrorEqualityUsesMappedSeshatErrorOnly() {
        XCTAssertEqual(
            SessionState.error(.audioEngineFailure),
            SessionState.error(.audioEngineFailure)
        )
        XCTAssertNotEqual(
            SessionState.error(.audioEngineFailure),
            SessionState.error(.transcriptionFailure)
        )
    }
}
