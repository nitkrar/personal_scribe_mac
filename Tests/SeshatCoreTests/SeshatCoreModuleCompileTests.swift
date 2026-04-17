import XCTest
@testable import SeshatCore

final class SeshatCoreModuleCompileTests: XCTestCase {
    func testModuleCompiles() {
        _ = SeshatCoreModule.self
        XCTAssertTrue(true)
    }
}
