import XCTest
@testable import SeshatSession

final class SeshatSessionModuleCompileTests: XCTestCase {
    func testModuleCompiles() {
        _ = SeshatSessionModule.self
        XCTAssertTrue(true)
    }
}
