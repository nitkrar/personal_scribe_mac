import XCTest
import SeshatCore
import SeshatTestSupport
@testable import SeshatSession

final class SessionCoordinatorErrorTests: XCTestCase {
    func testCaptureFailureMapsToErrorAndNextToggleRetries() async throws {
        let capture = FakeAudioCapturing(error: .audioEngineFailure)
        let transcriber = FakeTranscriber(
            result: .init(
                text: "retry",
                audioDuration: .zero,
                processingDuration: .zero
            )
        )
        let coordinator = SessionCoordinator(
            capture: capture,
            transcriber: transcriber,
            logger: SeshatLogger(category: SeshatLogCategory.session)
        )

        let stream = await coordinator.stateStream()
        let observedTask = Task { () -> [SessionState] in
            var observed: [SessionState] = []
            for await state in stream.prefix(5) {
                observed.append(state)
            }
            return observed
        }

        await coordinator.toggle()
        try await Task.sleep(for: .milliseconds(50))
        await coordinator.toggle()

        let observed = try await withTimeout(.seconds(1)) {
            await observedTask.value
        }

        XCTAssertEqual(
            observed,
            [.idle, .recording, .error(.audioEngineFailure), .idle, .recording]
        )
        try await Task.sleep(for: .milliseconds(50))
        let retriedState = await coordinator.state()
        XCTAssertEqual(retriedState, .recording)

        await coordinator.toggle()
    }

    func testRepeatedToggleDuringTranscribingIsIgnoredAndLastResultSurvives() async throws {
        let buffer = try PCMBuffer(
            samples: Array(repeating: 0, count: 16_000),
            timestamp: ContinuousClock().now
        )
        let capture = FakeAudioCapturing(buffers: [buffer])
        let transcriber = FakeTranscriber(
            result: .init(
                text: "hello",
                audioDuration: .seconds(1),
                processingDuration: .seconds(0.2)
            ),
            delay: .milliseconds(200)
        )
        let coordinator = SessionCoordinator(
            capture: capture,
            transcriber: transcriber,
            logger: SeshatLogger(category: SeshatLogCategory.session)
        )

        let stream = await coordinator.stateStream()
        let observedTask = Task { () -> [SessionState] in
            var observed: [SessionState] = []
            for await state in stream.prefix(4) {
                observed.append(state)
            }
            return observed
        }

        let toggleTask = Task {
            await coordinator.toggle()
            await coordinator.toggle()
        }

        try await Task.sleep(for: .milliseconds(50))
        await coordinator.toggle()

        await toggleTask.value
        let observed = try await withTimeout(.seconds(1)) {
            await observedTask.value
        }
        let lastResult = await coordinator.lastResult()

        XCTAssertEqual(observed, [.idle, .recording, .transcribing, .idle])
        XCTAssertEqual(lastResult?.text, "Hello.")
    }

    func testStopPathPreservesErrorWhenCaptureFailsMidStop() async throws {
        let buffer = try PCMBuffer(
            samples: [Float](repeating: 0, count: 16_000),
            sampleRate: 16_000,
            channelCount: 1,
            timestamp: ContinuousClock().now
        )
        let capture = FailingOnStopCapture(buffer: buffer, error: .audioEngineFailure)
        let transcriber = FakeTranscriber(
            result: TranscriptionResult(
                text: "should not appear",
                audioDuration: .seconds(1),
                processingDuration: .seconds(0.1)
            )
        )
        let coordinator = SessionCoordinator(
            capture: capture,
            transcriber: transcriber,
            logger: SeshatLogger(category: SeshatLogCategory.session)
        )

        let stream = await coordinator.stateStream()
        await coordinator.toggle()
        await coordinator.toggle()

        var observed: [SessionState] = []
        for await state in stream.prefix(3) {
            observed.append(state)
        }

        let finalState = await coordinator.state()
        let lastResult = await coordinator.lastResult()

        XCTAssertEqual(observed, [.idle, .recording, .error(.audioEngineFailure)])
        XCTAssertEqual(finalState, .error(.audioEngineFailure))
        XCTAssertNil(lastResult, "transcription must not run when capture failed")
    }

    private func withTimeout<T: Sendable>(
        _ duration: Duration,
        operation: @escaping @Sendable () async -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                await operation()
            }
            group.addTask {
                try await Task.sleep(for: duration)
                throw TimeoutError()
            }

            let value = try await group.next()!
            group.cancelAll()
            return value
        }
    }

    private struct TimeoutError: Error {}

    private actor FailingOnStopCapture: AudioCapturing {
        private let buffer: PCMBuffer
        private let error: SeshatError
        private var continuation: AsyncThrowingStream<PCMBuffer, Error>.Continuation?
        private var isCapturing = false

        init(buffer: PCMBuffer, error: SeshatError) {
            self.buffer = buffer
            self.error = error
        }

        func start() async throws -> AsyncThrowingStream<PCMBuffer, Error> {
            guard !isCapturing else {
                throw SeshatError.audioEngineFailure
            }

            isCapturing = true
            var capturedContinuation: AsyncThrowingStream<PCMBuffer, Error>.Continuation?
            let stream = AsyncThrowingStream<PCMBuffer, Error> { continuation in
                capturedContinuation = continuation
            }
            continuation = capturedContinuation
            continuation?.yield(buffer)

            return stream
        }

        func stop() async {
            guard isCapturing else { return }
            isCapturing = false
            continuation?.finish(throwing: error)
            continuation = nil
        }
    }
}
