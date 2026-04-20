import XCTest
@testable import PersonalScribeCore

final class TranscriptionResultScaffoldingTests: XCTestCase {
    func testTranscriptionResultSymbolCompiles() {
        _ = TranscriptionResult(
            text: "",
            audioDuration: .zero,
            processingDuration: .zero
        )
        XCTAssertTrue(true)
    }
}
