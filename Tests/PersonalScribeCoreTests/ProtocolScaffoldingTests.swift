import XCTest
@testable import PersonalScribeCore

final class ProtocolScaffoldingTests: XCTestCase {
    func testProtocolSymbolsCompile() {
        _ = AudioCapturing.self
        _ = Transcribing.self
        _ = ModelDownloadProgress.self
        XCTAssertTrue(true)
    }
}
