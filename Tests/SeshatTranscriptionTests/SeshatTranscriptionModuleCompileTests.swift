import XCTest
@testable import SeshatTranscription

final class SeshatTranscriptionModuleCompileTests: XCTestCase {
    func testModuleCompiles() {
        _ = SeshatTranscriptionModule.self
        XCTAssertTrue(true)
    }
}
