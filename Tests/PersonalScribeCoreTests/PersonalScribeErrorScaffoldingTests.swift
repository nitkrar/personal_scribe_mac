import XCTest
@testable import PersonalScribeCore

final class PersonalScribeErrorScaffoldingTests: XCTestCase {
    func testPersonalScribeErrorSymbolCompiles() {
        _ = PersonalScribeError.self
        XCTAssertTrue(true)
    }
}
