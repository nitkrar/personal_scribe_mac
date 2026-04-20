import XCTest
@testable import PersonalScribeSession

final class PersonalScribeSessionModuleCompileTests: XCTestCase {
    func testModuleCompiles() {
        _ = PersonalScribeSessionModule.self
        XCTAssertTrue(true)
    }
}
