import XCTest
import PersonalScribeCore
@testable import PersonalScribeTestSupport

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
            XCTAssertEqual(error as? PersonalScribeError, .audioEngineFailure)
        }
    }

    func testFakeCaptureStreamStaysOpenAfterPresetBuffersExhaust() async throws {
        let buffer = try PCMBuffer(
            samples: [0.0],
            sampleRate: 16_000,
            channelCount: 1,
            timestamp: ContinuousClock().now
        )
        let capture = FakeAudioCapturing(buffers: [buffer])
        let stream = try await capture.start()
        var iterator = stream.makeAsyncIterator()

        let first = try await iterator.next()
        XCTAssertNotNil(first)

        async let next = iterator.next()
        await capture.stop()
        let terminated = try await next

        XCTAssertNil(terminated, "stream finishes only after stop(), not preset exhaustion")
    }

    func testFakeCaptureStopIsIdempotent() async throws {
        let capture = FakeAudioCapturing()

        _ = try await capture.start()
        await capture.stop()
        await capture.stop()
    }

    func testFakeCaptureThrowsProgrammedErrorAfterPresetBuffers() async throws {
        let buffer = try PCMBuffer(
            samples: [0.0],
            sampleRate: 16_000,
            channelCount: 1,
            timestamp: ContinuousClock().now
        )
        let capture = FakeAudioCapturing(buffers: [buffer], error: .resampleFailure)
        let stream = try await capture.start()
        let levelStream = await capture.audioLevelStream()
        var levelIterator = levelStream.makeAsyncIterator()
        var caughtError: PersonalScribeError?

        do {
            for try await _ in stream {}
        } catch let error as PersonalScribeError {
            caughtError = error
        }

        XCTAssertEqual(caughtError, .resampleFailure)
        let finished = expectation(description: "level stream finishes on programmed error")
        Task {
            _ = await levelIterator.next()
            finished.fulfill()
        }
        await fulfillment(of: [finished], timeout: 1.0)
    }

    func testFakeCaptureStreamFinishesExactlyOnceOnStop() async throws {
        let capture = FakeAudioCapturing()
        let stream = try await capture.start()
        var iterator = stream.makeAsyncIterator()

        await capture.stop()

        let firstTermination = try await iterator.next()
        let secondTermination = try await iterator.next()

        XCTAssertNil(firstTermination)
        XCTAssertNil(secondTermination)
    }
}
