import XCTest
@testable import PersonalScribeTranscription

final class PersonalScribeTranscriptionModuleCompileTests: XCTestCase {
    func testModuleCompiles() {
        _ = PersonalScribeTranscriptionModule.self
        XCTAssertTrue(true)
    }
}
