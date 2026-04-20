import XCTest
@testable import SeshatCore

final class ProtocolScaffoldingTests: XCTestCase {
    func testProtocolSymbolsCompile() {
        _ = AudioCapturing.self
        _ = Transcribing.self
        _ = ModelDownloadProgress.self
        XCTAssertTrue(true)
    }
}
