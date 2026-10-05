import XCTest
import PersonalScribeCore
import PersonalScribeTestSupport
@testable import PersonalScribeSession

final class SessionCoordinatorHappyPathTests: XCTestCase {
    func testBeforeCaptureStartsHandlerRunsForToggleAndHoldStarts() async throws {
        let counter = StartHookCounter()
        let coordinator = SessionCoordinator(
            capture: FakeAudioCapturer(buffers: []),
            transcriber: FakeTranscriber(result: .init(text: "", audioDuration: .zero, processingDuration: .zero)),
            logger: PersonalScribeLogger.testing(category: PersonalScribeLogCategory.session)
        )
        await coordinator.setBeforeCaptureStartsHandler {
            await counter.increment()
        }

        await coordinator.toggle()
        await coordinator.stopIfActive()
        await coordinator.startHoldIfIdle()

        let count = await counter.value()
        XCTAssertEqual(count, 2)
    }

    func testApplicationTerminationFinalizesDuringPausedResumeTransition() async throws {
        let capture = CoordinatorResumeGatedCapture(
            buffer: try PCMBuffer(
                samples: Array(repeating: 0.1, count: 16_000),
                timestamp: ContinuousClock().now
            )
        )
        let sink = CoordinatorOutputSink()
        let coordinator = SessionCoordinator(
            capture: capture,
            transcriber: FakeTranscriber(
                result: .init(
                    text: "held",
                    audioDuration: .seconds(1),
                    processingDuration: .zero
                )
            ),
            logger: PersonalScribeLogger.testing(category: PersonalScribeLogCategory.session),
            outputSink: sink
        )

        await coordinator.toggle()
        await coordinator.pauseIfRecording()
        let resume = Task { await coordinator.resumeIfPaused() }
        await capture.waitUntilResumeStart()
        await coordinator.finishForApplicationTermination()

        let sinks = await sink.deliverySinks()
        XCTAssertEqual(sinks, [[.clipboard(restoreEnabled: false)]])

        await capture.releaseResumeStart()
        await resume.value
        let captureState = await capture.state()
        XCTAssertEqual(captureState.stopCount, 2)
        XCTAssertFalse(captureState.isRunning)
    }

    func testCancelIfActiveCancelsPausedSessionIntoResumableCardState() async throws {
        let buffer = try PCMBuffer(
            samples: Array(repeating: 0.1, count: 16_000),
            timestamp: ContinuousClock().now
        )
        let coordinator = SessionCoordinator(
            capture: FakeAudioCapturer(buffers: [buffer]),
            transcriber: FakeTranscriber(
                result: .init(
                    text: "held",
                    audioDuration: .seconds(1),
                    processingDuration: .zero
                )
            ),
            logger: PersonalScribeLogger.testing(category: PersonalScribeLogCategory.session)
        )

        await coordinator.toggle()
        await coordinator.pauseIfRecording()
        let pausedState = await coordinator.state()
        XCTAssertEqual(pausedState, .paused)

        await coordinator.cancelIfActive()

        let snapshot = await coordinator.snapshot()
        XCTAssertEqual(snapshot.sessionState, .idle)
        XCTAssertTrue(snapshot.cancelledCaptureResumable)
    }

    /// Regression: before the pipeline/coordinator state consolidation,
    /// `SessionCoordinator` observed pipeline snapshots through two
    /// unsynchronized paths — a direct post-call `refreshFromPipelineSnapshot()`
    /// and a background stream observer — which could reorder and republish a
    /// stale `.transcribing` snapshot AFTER the terminal `.idle` on a
    /// successful stop, producing the pill flicker
    /// `.transcribing → .done → .transcribing → .done`. See
    /// `plans/investigations/2026-04-23-pill-flicker-root-cause-codex.md`.
    /// This test pins the single-source-of-truth fix: no pre-terminal state
    /// may appear after the terminal `.idle` within a grace window.
    func testStateStreamNeverRepublishesPreTerminalAfterStopIdle() async throws {
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
            )
        )
        let coordinator = SessionCoordinator(
            capture: capture,
            transcriber: transcriber,
            logger: PersonalScribeLogger.testing(category: PersonalScribeLogCategory.session)
        )

        let stream = await coordinator.stateStream()
        let collector = Task { () -> [SessionState] in
            var observed: [SessionState] = []
            for await state in stream {
                observed.append(state)
            }
            return observed
        }

        await coordinator.toggle()
        await coordinator.toggle()

        try await withTimeout(.seconds(2)) {
            while await coordinator.lastResult() == nil {
                try? await Task.sleep(for: .milliseconds(10))
            }
        }
        try await Task.sleep(for: .milliseconds(200))

        collector.cancel()
        let observed = await collector.value

        XCTAssertEqual(
            observed,
            [.idle, .capturing, .transcribing, .idle],
            "State stream must settle at terminal .idle with no stale pre-terminal republish."
        )
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
}

private actor StartHookCounter {
    private var count = 0
    func increment() { count += 1 }
    func value() -> Int { count }
}

private actor CoordinatorResumeGatedCapture: AudioCapturer {
    private let buffer: PCMBuffer
    private var startCount = 0
    private var streamContinuation: AsyncThrowingStream<PCMBuffer, Error>.Continuation?
    private var resumeStarted = false
    private var resumeReleased = false
    private var isRunning = false
    private var stopCount = 0
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

    init(buffer: PCMBuffer) {
        self.buffer = buffer
    }

    func start() async throws -> AsyncThrowingStream<PCMBuffer, Error> {
        startCount += 1
        if startCount == 2 {
            resumeStarted = true
            let pending = startWaiters
            startWaiters.removeAll()
            pending.forEach { $0.resume() }
            if !resumeReleased {
                await withCheckedContinuation { releaseWaiters.append($0) }
            }
        }
        isRunning = true
        return AsyncThrowingStream { continuation in
            streamContinuation = continuation
            if startCount == 1 {
                continuation.yield(buffer)
            }
        }
    }

    func stop() async {
        stopCount += 1
        isRunning = false
        streamContinuation?.finish()
        streamContinuation = nil
    }

    func audioLevelStream() async -> AsyncStream<Float> {
        AsyncStream { $0.finish() }
    }

    func waitUntilResumeStart() async {
        if resumeStarted { return }
        await withCheckedContinuation { startWaiters.append($0) }
    }

    func releaseResumeStart() {
        resumeReleased = true
        let pending = releaseWaiters
        releaseWaiters.removeAll()
        pending.forEach { $0.resume() }
    }

    func state() -> (stopCount: Int, isRunning: Bool) {
        (stopCount, isRunning)
    }
}

private actor CoordinatorOutputSink: PipelineOutputSink {
    private var sinks: [[BoundOutputSink]] = []

    func deliverPartial(_ revision: TranscriptProgress) async throws {}

    func deliverFinal(_ result: TranscriptionResult, sinks: [BoundOutputSink]) async throws -> String? {
        self.sinks.append(sinks)
        return nil
    }

    func resetForNewSession() async {}

    func deliverySinks() -> [[BoundOutputSink]] {
        sinks
    }
}
