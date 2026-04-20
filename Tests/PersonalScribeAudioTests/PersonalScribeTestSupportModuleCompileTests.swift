import XCTest
@testable import PersonalScribeTestSupport

final class PersonalScribeTestSupportModuleCompileTests: XCTestCase {
    func testModuleCompiles() {
        _ = PersonalScribeTestSupportModule.self
        XCTAssertTrue(true)
    }
}
