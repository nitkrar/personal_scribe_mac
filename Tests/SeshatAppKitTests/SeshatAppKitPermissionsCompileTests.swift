import XCTest
@testable import SeshatAppKit

final class SeshatAppKitPermissionsCompileTests: XCTestCase {
    func testPermissionsModuleCompiles() {
        _ = SeshatAppKitPermissionsModule.self
        XCTAssertTrue(true)
    }
}
