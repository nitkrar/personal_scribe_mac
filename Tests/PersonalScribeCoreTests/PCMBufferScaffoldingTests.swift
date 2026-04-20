import XCTest
@testable import PersonalScribeCore

final class PCMBufferScaffoldingTests: XCTestCase {
    func testPCMBufferSymbolCompiles() throws {
        _ = try PCMBuffer(
            samples: [],
            timestamp: ContinuousClock().now
        )
        XCTAssertTrue(true)
    }
}
