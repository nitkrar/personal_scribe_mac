import XCTest
@testable import PersonalScribeCore

final class SessionStateTests: XCTestCase {
    func testErrorEqualityUsesMappedPersonalScribeErrorOnly() {
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
