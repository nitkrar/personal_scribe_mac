import XCTest
import SeshatCore
import SeshatTestSupport
@testable import SeshatSession

final class SessionCoordinatorPreparationTests: XCTestCase {
    func testStopCompletesWhileBackgroundPrepareIsStillRunning() async throws {
        let buffer = try PCMBuffer(
            samples: Array(repeating: 0.25, count: 1_600),
            timestamp: ContinuousClock().now
        )
        let transcriber = SlowPrepareTranscriber(
            result: .init(
                text: "hello",
                audioDuration: .milliseconds(100),
                processingDuration: .milliseconds(50)
            )
        )
        let coordinator = SessionCoordinator(
            capture: FakeAudioCapturing(buffers: [buffer]),
            transcriber: transcriber,
            logger: SeshatLogger(category: SeshatLogCategory.session)
        )

        defer {
            Task {
                await transcriber.releasePrepare()
            }
        }

        await coordinator.toggle()
        await transcriber.waitUntilPrepareStarted()

        let stopTask = Task {
            await coordinator.toggle()
        }

        try await withTimeout(.seconds(1)) {
            await stopTask.value
        }

        let state = await coordinator.state()
        let result = await coordinator.lastResult()
        let transcribeCallCount = await transcriber.transcribeCallCount()

        XCTAssertEqual(state, .idle)
        XCTAssertEqual(result?.text, "Hello.")
        XCTAssertEqual(transcribeCallCount, 1)
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

private actor SlowPrepareTranscriber: Transcribing {
    private let result: TranscriptionResult
    private var didStartPrepare = false
    private var prepareContinuation: CheckedContinuation<Void, Never>?
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var transcribeCount = 0

    init(result: TranscriptionResult) {
        self.result = result
    }

    func prepare() async throws {
        didStartPrepare = true
        let waiters = startWaiters
        startWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }

        await withCheckedContinuation { continuation in
            prepareContinuation = continuation
        }
    }

    nonisolated func modelDownloadProgress() -> AsyncStream<ModelDownloadProgress> {
        AsyncStream { continuation in
            continuation.yield(
                .init(phase: .idle, fractionCompleted: 0, receivedBytes: 0, expectedBytes: nil)
            )
            continuation.finish()
        }
    }

    func transcribe(_ audio: PCMBuffer) async throws -> TranscriptionResult {
        transcribeCount += 1
        return result
    }

    func transcribe(stream: AsyncThrowingStream<PCMBuffer, Error>) async throws -> TranscriptionResult {
        for try await _ in stream {}
        transcribeCount += 1
        return result
    }

    func waitUntilPrepareStarted() async {
        if didStartPrepare {
            return
        }

        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func releasePrepare() {
        prepareContinuation?.resume()
        prepareContinuation = nil
    }

    func transcribeCallCount() -> Int {
        transcribeCount
    }
}
