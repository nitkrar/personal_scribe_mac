import XCTest
@testable import SeshatCore

final class SeshatLoggerScaffoldingTests: XCTestCase {
    func testSeshatLoggerSymbolCompiles() {
        _ = SeshatLogger.self
        XCTAssertTrue(true)
    }
}
