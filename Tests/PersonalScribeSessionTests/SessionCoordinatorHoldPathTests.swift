import XCTest
import PersonalScribeCore
import PersonalScribeTestSupport
@testable import PersonalScribeSession

final class SessionCoordinatorHoldPathTests: XCTestCase {
    func testStartIfIdleFromIdleStartsRecording() async throws {
        let coordinator = try makeCoordinator()

        await coordinator.startIfIdle()

        let state = await coordinator.state()
        XCTAssertEqual(state, .recording)

        try await Task.sleep(for: .milliseconds(50))
        await coordinator.stopIfRecording()
    }

    func testStartIfIdleFromRecordingIsNoOp() async throws {
        let coordinator = try makeCoordinator()

        await coordinator.startIfIdle()
        try await Task.sleep(for: .milliseconds(50))

        await coordinator.startIfIdle()

        let state = await coordinator.state()
        let lastResult = await coordinator.lastResult()

        XCTAssertEqual(state, .recording)
        XCTAssertNil(lastResult)

        await coordinator.stopIfRecording()
    }

    func testStartIfIdleFromTranscribingIsNoOp() async throws {
        let coordinator = try makeCoordinator(transcriberDelay: .milliseconds(200))

        await coordinator.startIfIdle()
        try await Task.sleep(for: .milliseconds(50))

        let stopTask = Task {
            await coordinator.stopIfRecording()
        }

        try await waitUntilState(.transcribing, coordinator: coordinator)
        await coordinator.startIfIdle()

        let stateDuringTranscribing = await coordinator.state()
        XCTAssertEqual(stateDuringTranscribing, .transcribing)

        await stopTask.value
        // `stopIfRecording` returns before transcription finishes
        // flushing to `.idle`; poll instead of snapshotting.
        try await waitUntilState(.idle, coordinator: coordinator)
    }

    func testStopIfRecordingFromRecordingStopsSession() async throws {
        let coordinator = try makeCoordinator()

        await coordinator.startIfIdle()
        try await Task.sleep(for: .milliseconds(50))
        await coordinator.stopIfRecording()

        let state = await coordinator.state()
        let lastResult = await coordinator.lastResult()

        XCTAssertEqual(state, .idle)
        XCTAssertEqual(lastResult?.text, "Hello.")
    }

    func testStopIfRecordingFromIdleIsNoOp() async throws {
        let coordinator = try makeCoordinator()

        await coordinator.stopIfRecording()

        let state = await coordinator.state()
        let lastResult = await coordinator.lastResult()

        XCTAssertEqual(state, .idle)
        XCTAssertNil(lastResult)
    }

    func testStopIfRecordingFromTranscribingIsNoOp() async throws {
        let coordinator = try makeCoordinator(transcriberDelay: .milliseconds(200))

        await coordinator.startIfIdle()
        try await Task.sleep(for: .milliseconds(50))

        let stopTask = Task {
            await coordinator.stopIfRecording()
        }

        try await waitUntilState(.transcribing, coordinator: coordinator)
        await coordinator.stopIfRecording()

        let stateDuringTranscribing = await coordinator.state()
        XCTAssertEqual(stateDuringTranscribing, .transcribing)

        await stopTask.value
        // `stopIfRecording` returns before transcription finishes
        // flushing to `.idle`; poll instead of snapshotting.
        try await waitUntilState(.idle, coordinator: coordinator)
    }

    func testOnHoldReleaseWithoutPriorStartDoesNotStartRecording() async throws {
        let coordinator = try makeCoordinator()

        await coordinator.stopIfRecording()

        let state = await coordinator.state()
        let lastResult = await coordinator.lastResult()

        XCTAssertEqual(state, .idle)
        XCTAssertNil(lastResult)
    }

    private func makeCoordinator(transcriberDelay: Duration? = nil) throws -> SessionCoordinator {
        let buffer = try PCMBuffer(
            samples: Array(repeating: 0, count: 16_000),
            timestamp: ContinuousClock().now
        )

        return SessionCoordinator(
            capture: FakeAudioCapturing(buffers: [buffer]),
            transcriber: FakeTranscriber(
                result: .init(
                    text: "hello",
                    audioDuration: .seconds(1),
                    processingDuration: .seconds(0.2)
                ),
                delay: transcriberDelay
            ),
            logger: PersonalScribeLogger(category: PersonalScribeLogCategory.session)
        )
    }

    private func waitUntilState(
        _ expected: SessionState,
        coordinator: SessionCoordinator
    ) async throws {
        try await withTimeout(.seconds(1)) {
            while await coordinator.state() != expected {
                try Task.checkCancellation()
                try await Task.sleep(for: .milliseconds(10))
            }
        }
    }

    private func withTimeout<T: Sendable>(
        _ duration: Duration,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
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
