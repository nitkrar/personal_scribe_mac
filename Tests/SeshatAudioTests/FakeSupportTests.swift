import XCTest
import SeshatCore
@testable import SeshatTestSupport

final class FakeSupportTests: XCTestCase {
    func testFakeTranscriberReturnsPresetResult() async throws {
        let expected = TranscriptionResult(
            text: "hello",
            audioDuration: .seconds(1),
            processingDuration: .seconds(0.2)
        )
        let transcriber = FakeTranscriber(result: expected)
        let buffer = try PCMBuffer(
            samples: Array(repeating: 0, count: 16_000),
            timestamp: ContinuousClock().now
        )

        let result = try await transcriber.transcribe(buffer)

        XCTAssertEqual(result, expected)
    }

    func testFakeAudioCapturingRejectsSecondStart() async throws {
        let capture = FakeAudioCapturing()

        _ = try await capture.start()

        do {
            _ = try await capture.start()
            XCTFail("Expected second start to fail")
        } catch {
            XCTAssertEqual(error as? SeshatError, .audioEngineFailure)
        }
    }
}
