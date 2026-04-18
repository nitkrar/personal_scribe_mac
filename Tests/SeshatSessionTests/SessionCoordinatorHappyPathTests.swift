import XCTest
import SeshatCore
import SeshatTestSupport
@testable import SeshatSession

final class SessionCoordinatorHappyPathTests: XCTestCase {
    func testToggleWalksIdleRecordingTranscribingIdle() async throws {
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
            for await state in stream.prefix(4) {
                observed.append(state)
            }
            return observed
        }
        let toggleTask = Task {
            await coordinator.toggle()
            await coordinator.toggle()
        }

        await toggleTask.value
        let observed = try await withTimeout(.seconds(1)) {
            await observedTask.value
        }
        let lastResult = await coordinator.lastResult()

        XCTAssertEqual(observed, [.idle, .recording, .transcribing, .idle])
        XCTAssertEqual(lastResult?.text, "Hello.")
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
