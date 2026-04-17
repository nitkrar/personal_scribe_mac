import XCTest
@testable import SeshatCore

final class SeshatConfigScaffoldingTests: XCTestCase {
    func testSeshatConfigSymbolCompiles() {
        _ = SeshatConfig.self
        XCTAssertTrue(true)
    }
}
