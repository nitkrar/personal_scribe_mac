import XCTest
@testable import SeshatAppKit

final class SeshatAppKitShellCompileTests: XCTestCase {
    func testShellCompiles() {
        _ = SeshatAppPlaceholder.self
        _ = AppDelegatePlaceholder.self
        XCTAssertTrue(true)
    }
}
