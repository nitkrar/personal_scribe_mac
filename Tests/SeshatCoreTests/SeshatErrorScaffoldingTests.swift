import XCTest
@testable import SeshatCore

final class SeshatErrorScaffoldingTests: XCTestCase {
    func testSeshatErrorSymbolCompiles() {
        _ = SeshatError.self
        XCTAssertTrue(true)
    }
}
