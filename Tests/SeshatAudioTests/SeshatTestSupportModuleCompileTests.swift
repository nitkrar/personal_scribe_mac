import XCTest
@testable import SeshatTestSupport

final class SeshatTestSupportModuleCompileTests: XCTestCase {
    func testModuleCompiles() {
        _ = SeshatTestSupportModule.self
        XCTAssertTrue(true)
    }
}
