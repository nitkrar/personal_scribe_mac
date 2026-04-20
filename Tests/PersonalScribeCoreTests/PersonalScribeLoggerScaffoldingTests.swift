import XCTest
@testable import PersonalScribeCore

final class PersonalScribeLoggerScaffoldingTests: XCTestCase {
    func testPersonalScribeLoggerSymbolCompiles() {
        _ = PersonalScribeLogger.self
        XCTAssertTrue(true)
    }
}
