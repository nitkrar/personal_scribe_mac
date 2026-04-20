import XCTest
import PersonalScribeCore
@testable import PersonalScribeTranscription

final class SingleBufferTranscriptionTests: PersonalScribeTranscriptionFilesystemTestCase {
    func testTranscribeMapsCannedInferenceResult() async throws {
        let audio = try PCMBuffer(
            samples: Array(repeating: 0.1, count: 16_000),
            sampleRate: 16_000,
            channelCount: 1,
            timestamp: .now
        )
        let transcriber = FluidAudioTranscriber(
            downloader: StubModelDownloader(),
            inference: StubInferenceClient(
                result: FluidAudioInferenceResult(
                    text: "hello world",
                    processingDuration: .milliseconds(120)
                )
            )
        )

        let result = try await transcriber.transcribe(audio)

        XCTAssertEqual(result.text, "hello world")
        XCTAssertEqual(result.segments, [])
        XCTAssertEqual(result.audioDuration, audio.duration)
        XCTAssertEqual(result.processingDuration, .milliseconds(120))
    }
}
