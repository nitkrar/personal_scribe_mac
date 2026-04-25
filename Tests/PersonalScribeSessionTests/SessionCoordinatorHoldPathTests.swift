import XCTest
import PersonalScribeCore
import PersonalScribeTestSupport
@testable import PersonalScribeSession

final class SessionCoordinatorHoldPathTests: XCTestCase {
    /// `#075`: `.shortExit` is a non-error terminal state. It must display
    /// as `.idle` so every entry-point guard (`startHoldIfIdle`,
    /// `startIfIdle`, `toggle`) accepts it as startable — otherwise the
    /// pipeline's short-hold termination wedges every entry point until
    /// something non-guarded re-arms the state machine.
    func testShortExitDisplayStateMapsToIdle() {
        XCTAssertEqual(SessionCoordinator.displayState(for: .shortExit), .idle)
    }

    /// `#075` wedge regression: after a short-hold publishes `.shortExit`,
    /// the next `startHoldIfIdle()` must start a new hold session. The
    /// pre-fix bug was that `.error(.recordingTooShort)` stuck around and
    /// `startHoldIfIdle`'s `.idle` guard rejected the second hold-press.
    func testStartHoldIfIdleFromShortExitEntersHoldRecording() async throws {
        let shortBuffer = try PCMBuffer(
            samples: Array(repeating: 0, count: 8_000),
            sampleRate: 16_000,
            channelCount: 1,
            timestamp: ContinuousClock().now
        )
        let coordinator = SessionCoordinator(
            capture: FakeAudioCapturer(buffers: [shortBuffer]),
            transcriber: FakeTranscriber(
                result: .init(
                    text: "hello",
                    audioDuration: .seconds(1),
                    processingDuration: .zero
                )
            ),
            logger: PersonalScribeLogger(category: PersonalScribeLogCategory.session)
        )

        // First hold: short release produces `.shortExit`.
        await coordinator.startHoldIfIdle()
        try await Task.sleep(for: .milliseconds(50))
        await coordinator.stopIfActive()

        // Observe the raw snapshot stream for `.shortExit` (which maps to
        // `.idle` in display-state, so `waitUntilState` won't see it).
        try await waitUntilRawState(.shortExit, coordinator: coordinator)

        let stateBeforeSecondHold = await coordinator.snapshot().sessionState
        XCTAssertEqual(
            stateBeforeSecondHold, .shortExit,
            "Precondition for wedge test: session should be in .shortExit before second hold."
        )

        // Second hold: must enter `.holdRecording`, not no-op.
        await coordinator.startHoldIfIdle()

        let stateAfterSecondHold = await coordinator.snapshot().sessionState
        XCTAssertEqual(
            stateAfterSecondHold, .holdRecording,
            "Wedge regression: hold-press from .shortExit must start a new hold session (#075)."
        )

        await coordinator.cancelIfActive()
    }

    private func waitUntilRawState(
        _ expected: SessionState,
        coordinator: SessionCoordinator
    ) async throws {
        try await withTimeout(.seconds(1)) {
            while await coordinator.snapshot().sessionState != expected {
                try Task.checkCancellation()
                try await Task.sleep(for: .milliseconds(10))
            }
        }
    }

    func testStartIfIdleFromIdleStartsRecording() async throws {
        let coordinator = try makeCoordinator()

        await coordinator.startIfIdle()

        let state = await coordinator.state()
        XCTAssertEqual(state, .capturing)

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

        XCTAssertEqual(state, .capturing)
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

    // MARK: - #071 — hold-path coordinator API

    func testStartHoldIfIdleFromIdleEntersHoldRecording() async throws {
        let coordinator = try makeCoordinator()

        await coordinator.startHoldIfIdle()

        let state = await coordinator.state()
        XCTAssertEqual(state, .holdRecording)

        try await Task.sleep(for: .milliseconds(50))
        await coordinator.stopIfActive()
    }

    func testStartHoldIfIdleFromRecordingIsNoOp() async throws {
        let coordinator = try makeCoordinator()

        await coordinator.startIfIdle()
        try await Task.sleep(for: .milliseconds(50))

        await coordinator.startHoldIfIdle()

        let state = await coordinator.state()
        XCTAssertEqual(state, .capturing, "startHoldIfIdle must not replace a running .capturing session")

        await coordinator.stopIfActive()
    }

    func testStartHoldIfIdleFromHoldRecordingIsNoOp() async throws {
        let coordinator = try makeCoordinator()

        await coordinator.startHoldIfIdle()
        try await Task.sleep(for: .milliseconds(50))

        await coordinator.startHoldIfIdle()

        let state = await coordinator.state()
        XCTAssertEqual(state, .holdRecording)

        await coordinator.stopIfActive()
    }

    func testStopIfActiveFromHoldRecordingTranscribesAndReturnsToIdle() async throws {
        let coordinator = try makeCoordinator()

        await coordinator.startHoldIfIdle()
        try await Task.sleep(for: .milliseconds(50))
        await coordinator.stopIfActive()

        let state = await coordinator.state()
        let lastResult = await coordinator.lastResult()

        XCTAssertEqual(state, .idle)
        XCTAssertEqual(lastResult?.text, "Hello.")
    }

    func testStopIfActiveFromRecordingTranscribesAndReturnsToIdle() async throws {
        let coordinator = try makeCoordinator()

        await coordinator.startIfIdle()
        try await Task.sleep(for: .milliseconds(50))
        await coordinator.stopIfActive()

        let state = await coordinator.state()
        let lastResult = await coordinator.lastResult()

        XCTAssertEqual(state, .idle)
        XCTAssertEqual(lastResult?.text, "Hello.")
    }

    func testStopIfActiveFromIdleIsNoOp() async throws {
        let coordinator = try makeCoordinator()

        await coordinator.stopIfActive()

        let state = await coordinator.state()
        let lastResult = await coordinator.lastResult()

        XCTAssertEqual(state, .idle)
        XCTAssertNil(lastResult)
    }

    // MARK: - #002 — cancelIfActive (true-discard)

    func testCancelIfActiveFromRecordingReturnsToIdleWithNoLastResult() async throws {
        let coordinator = try makeCoordinator()

        await coordinator.startIfIdle()
        try await waitUntilState(.capturing, coordinator: coordinator)

        await coordinator.cancelIfActive()

        let state = await coordinator.state()
        let lastResult = await coordinator.lastResult()

        XCTAssertEqual(state, .idle)
        XCTAssertNil(lastResult, "cancel must NOT produce a transcript")
    }

    func testCancelIfActiveFromHoldRecordingReturnsToIdleWithNoLastResult() async throws {
        let coordinator = try makeCoordinator()

        await coordinator.startHoldIfIdle()
        try await waitUntilState(.holdRecording, coordinator: coordinator)

        await coordinator.cancelIfActive()

        let state = await coordinator.state()
        let lastResult = await coordinator.lastResult()

        XCTAssertEqual(state, .idle)
        XCTAssertNil(lastResult)
    }

    func testCancelIfActiveFromIdleIsNoOp() async throws {
        let coordinator = try makeCoordinator()

        await coordinator.cancelIfActive()

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
            capture: FakeAudioCapturer(buffers: [buffer]),
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
