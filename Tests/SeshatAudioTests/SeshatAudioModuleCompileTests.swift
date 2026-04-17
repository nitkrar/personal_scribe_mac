import XCTest
@testable import SeshatAudio

final class SeshatAudioModuleCompileTests: XCTestCase {
    func testModuleCompiles() {
        _ = SeshatAudioModule.self
        XCTAssertTrue(true)
    }
}
