import XCTest
@testable import PersonalScribeCore

final class PersonalScribeCoreModuleCompileTests: XCTestCase {
    func testModuleCompiles() {
        _ = PersonalScribeCoreModule.self
        XCTAssertTrue(true)
    }
}
