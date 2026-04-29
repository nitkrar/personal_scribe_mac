import XCTest
import PersonalScribeCore
import PersonalScribeTestSupport
@testable import PersonalScribeSession

/// #078.28 — `SessionCoordinator` re-validates the active recipe at
/// session start (per L15). If validation fails, the coordinator
/// publishes an `.error(.invalidActiveMode)` and aborts the session
/// without starting capture.
final class SessionCoordinatorValidationTests: XCTestCase {

    /// When the registry's active mode references a kind that has no
    /// active descriptor (per the `availableKinds` snapshot), the
    /// coordinator must NOT start capture and must publish an error.
    func testSessionStartRevalidatesActiveModeAndFailsWithDescriptiveErrorIfInvalid() async throws {
        let buffer = try PCMBuffer(
            samples: Array(repeating: 0, count: 16_000),
            timestamp: ContinuousClock().now
        )
        let capture = FakeAudioCapturer(buffers: [buffer])
        let transcriber = FakeTranscriber(
            result: TranscriptionResult(
                text: "should not be reached",
                audioDuration: .seconds(1),
                processingDuration: .zero
            )
        )

        // Registry seeded with a custom mode that requires .streamingASR
        // but only .asr is available — validation must fail.
        let needsStreaming = WorkflowMode(
            id: "needs-streaming",
            name: "Needs streaming",
            pipelineShape: .streaming,
            processors: [.streamingTranscriber(kind: .streamingASR)],
            captureControllers: [.manualHotkey],
            outputSinks: [.frontmostPaste(enabled: .override(true))]
        )
        let store = InMemoryWorkflowModeStore(
            initial: WorkflowModeDocument(
                defaultModeID: "needs-streaming",
                customModes: [needsStreaming]
            )
        )
        // Construct registry with `availableKinds = [.asr, .streamingASR]`
        // so initial load + activate-time validation both pass; then
        // shrink the available kinds at session-start time to simulate
        // a model becoming unavailable mid-app-session.
        let registry = try WorkflowModeRegistry(
            store: store,
            availableKindsProvider: { [.asr, .streamingASR] }
        )
        // Now build a coordinator that probes `availableKinds` =
        // `[.asr]` at session start — this triggers re-validation
        // failure on `.streamingASR`.
        let coordinator = SessionCoordinator(
            capture: capture,
            transcriber: transcriber,
            logger: PersonalScribeLogger(category: PersonalScribeLogCategory.session),
            workflowModeRegistry: registry,
            availableKindsProvider: { [.asr] }
        )

        await coordinator.startIfIdle()
        // Allow validation + error publish to land.
        try await Task.sleep(for: .milliseconds(50))

        let state = await coordinator.state()
        guard case .error(let mappedError) = state else {
            XCTFail("Expected .error after invalid-mode validation; got \(state)")
            return
        }
        XCTAssertEqual(mappedError, .invalidActiveMode)

        // Capture must NOT have been started: the snapshot's
        // recordingDuration stays nil because `startRecording()` never
        // executed, and `lastResult` is never produced.
        let snapshot = await coordinator.snapshot()
        XCTAssertNil(snapshot.recordingDuration,
                     "Capture must not start when active recipe fails validation")
        let lastResult = await coordinator.lastResult()
        XCTAssertNil(lastResult,
                     "Transcription must not run when active recipe fails validation")
    }

    /// Happy path: when validation passes, the coordinator proceeds
    /// normally into `.capturing` (no error).
    func testSessionStartProceedsWhenActiveModeValidates() async throws {
        let buffer = try PCMBuffer(
            samples: Array(repeating: 0, count: 16_000),
            timestamp: ContinuousClock().now
        )
        let capture = FakeAudioCapturer(buffers: [buffer])
        let transcriber = FakeTranscriber(
            result: TranscriptionResult(
                text: "ok",
                audioDuration: .seconds(1),
                processingDuration: .zero
            )
        )
        let store = InMemoryWorkflowModeStore() // built-in dictation as active.
        let registry = try WorkflowModeRegistry(
            store: store,
            availableKindsProvider: { [.asr] }
        )
        let coordinator = SessionCoordinator(
            capture: capture,
            transcriber: transcriber,
            logger: PersonalScribeLogger(category: PersonalScribeLogCategory.session),
            workflowModeRegistry: registry,
            availableKindsProvider: { [.asr] }
        )

        await coordinator.startIfIdle()
        // Wait briefly for capture to start.
        try await withTimeout(.seconds(1)) {
            while await coordinator.state() != .capturing {
                try? await Task.sleep(for: .milliseconds(10))
            }
        }

        let state = await coordinator.state()
        XCTAssertEqual(state, .capturing)

        await coordinator.cancelIfActive()
    }

    /// Backwards-compat: a coordinator constructed without a registry
    /// (legacy callers) skips validation entirely.
    func testLegacySessionCoordinatorWithoutRegistryStillStarts() async throws {
        let buffer = try PCMBuffer(
            samples: Array(repeating: 0, count: 16_000),
            timestamp: ContinuousClock().now
        )
        let capture = FakeAudioCapturer(buffers: [buffer])
        let transcriber = FakeTranscriber(
            result: TranscriptionResult(
                text: "ok",
                audioDuration: .seconds(1),
                processingDuration: .zero
            )
        )
        let coordinator = SessionCoordinator(
            capture: capture,
            transcriber: transcriber,
            logger: PersonalScribeLogger(category: PersonalScribeLogCategory.session)
        )

        await coordinator.startIfIdle()
        try await withTimeout(.seconds(1)) {
            while await coordinator.state() != .capturing {
                try? await Task.sleep(for: .milliseconds(10))
            }
        }
        let state = await coordinator.state()
        XCTAssertEqual(state, .capturing)

        await coordinator.cancelIfActive()
    }

    // MARK: - WorkflowModeRegistry.validateCurrentForSessionStart unit

    /// Direct unit on the registry: returns the active mode when
    /// validation passes.
    func testRegistryValidateActiveReturnsModeOnSuccess() throws {
        let store = InMemoryWorkflowModeStore() // built-in dictation
        let registry = try WorkflowModeRegistry(
            store: store,
            availableKindsProvider: { [.asr] }
        )

        let validated = try registry.validateCurrentForSessionStart(availableKinds: [.asr])
        XCTAssertEqual(validated.id, "dictation")
    }

    /// Direct unit on the registry: throws when the active mode's
    /// referenced kind is not in `availableKinds`.
    func testRegistryValidateActiveThrowsOnMissingKind() throws {
        let custom = WorkflowMode(
            id: "needs-streaming",
            name: "Needs streaming",
            pipelineShape: .streaming,
            processors: [.streamingTranscriber(kind: .streamingASR)],
            captureControllers: [.manualHotkey],
            outputSinks: [.frontmostPaste(enabled: .override(true))]
        )
        let store = InMemoryWorkflowModeStore(
            initial: WorkflowModeDocument(
                defaultModeID: "needs-streaming",
                customModes: [custom]
            )
        )
        let registry = try WorkflowModeRegistry(
            store: store,
            availableKindsProvider: { [.asr, .streamingASR] }
        )

        XCTAssertThrowsError(
            try registry.validateCurrentForSessionStart(availableKinds: [.asr])
        ) { error in
            XCTAssertEqual(
                error as? WorkflowModeValidationError,
                .kindUnavailable(.streamingASR)
            )
        }
    }

    // MARK: - Helpers

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
