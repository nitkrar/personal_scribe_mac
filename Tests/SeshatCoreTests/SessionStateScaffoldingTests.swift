import XCTest
@testable import SeshatCore

final class SessionStateScaffoldingTests: XCTestCase {
    func testSessionStateSymbolCompiles() {
        _ = SessionState.idle
        XCTAssertTrue(true)
    }
}
