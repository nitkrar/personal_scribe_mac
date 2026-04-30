import XCTest
import PersonalScribeCore
import PersonalScribeTestSupport
@testable import PersonalScribeSession

final class SessionCoordinatorHappyPathTests: XCTestCase {
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
