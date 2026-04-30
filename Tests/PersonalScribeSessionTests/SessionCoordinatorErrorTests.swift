import XCTest
import PersonalScribeCore
import PersonalScribeTestSupport
@testable import PersonalScribeSession

final class SessionCoordinatorErrorTests: XCTestCase {
    func testCaptureFailureMapsToErrorAndNextToggleRetries() async throws {
        let capture = FakeAudioCapturer(error: .audioEngineFailure)
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
            logger: PersonalScribeLogger.testing(category: PersonalScribeLogCategory.session)
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
            [.idle, .capturing, .error(.audioEngineFailure), .idle, .capturing]
        )
        try await Task.sleep(for: .milliseconds(50))
        let retriedState = await coordinator.state()
        XCTAssertEqual(retriedState, .capturing)

        await coordinator.toggle()
    }

    func testShortRecordingPublishesShortExitWithoutTranscribing() async throws {
        // Sub-1-second audio buffer: 8 000 samples at 16 kHz = 0.5 s.
        // FluidAudio rejects anything below 1 s with "Invalid audio
        // data"; coordinator short-circuits before calling the
        // transcriber and publishes `.shortExit` (non-error terminal)
        // so entry guards see `.idle` and no wedge happens. See `#075`.
        let shortBuffer = try PCMBuffer(
            samples: Array(repeating: 0, count: 8_000),
            sampleRate: 16_000,
            channelCount: 1,
            timestamp: ContinuousClock().now
        )
        let capture = FakeAudioCapturer(buffers: [shortBuffer])
        let transcriber = FakeTranscriber(
            result: .init(
                text: "should not be called",
                audioDuration: .milliseconds(500),
                processingDuration: .zero
            )
        )
        let coordinator = SessionCoordinator(
            capture: capture,
            transcriber: transcriber,
            logger: PersonalScribeLogger.testing(category: PersonalScribeLogCategory.session)
        )

        let snapshotStream = await coordinator.snapshotStream()
        let observedTask = Task { () -> [SessionState] in
            var observed: [SessionState] = []
            for await snapshot in snapshotStream {
                observed.append(snapshot.sessionState)
                if snapshot.sessionState == .shortExit {
                    break
                }
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
            observed.last, .shortExit,
            "Sub-1s recording must publish .shortExit (non-error terminal), not .error"
        )
        XCTAssertFalse(
            observed.contains(where: { state in
                if case .error = state { return true }
                return false
            }),
            "`.shortExit` must not be rendered through the `.error` channel"
        )
    }

    func testRepeatedToggleDuringTranscribingIsIgnoredAndLastResultSurvives() async throws {
        let buffer = try PCMBuffer(
            samples: Array(repeating: 0, count: 16_000),
            timestamp: ContinuousClock().now
        )
        let capture = FakeAudioCapturer(buffers: [buffer])
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
            logger: PersonalScribeLogger.testing(category: PersonalScribeLogCategory.session)
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

        XCTAssertEqual(observed, [.idle, .capturing, .transcribing, .idle])
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
            logger: PersonalScribeLogger.testing(category: PersonalScribeLogCategory.session)
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

        XCTAssertEqual(observed, [.idle, .capturing, .error(.audioEngineFailure)])
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

    private actor FailingOnStopCapture: AudioCapturer {
        private let buffer: PCMBuffer
        private let error: PersonalScribeError
        private var continuation: AsyncThrowingStream<PCMBuffer, Error>.Continuation?
        private var isCapturing = false

        init(buffer: PCMBuffer, error: PersonalScribeError) {
            self.buffer = buffer
            self.error = error
        }

        func start() async throws -> AsyncThrowingStream<PCMBuffer, Error> {
            guard !isCapturing else {
                throw PersonalScribeError.audioEngineFailure
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
