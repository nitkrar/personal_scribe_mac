import XCTest
@testable import PersonalScribeCore

final class SessionStateScaffoldingTests: XCTestCase {
    func testSessionStateSymbolCompiles() {
        _ = SessionState.idle
        XCTAssertTrue(true)
    }
}
