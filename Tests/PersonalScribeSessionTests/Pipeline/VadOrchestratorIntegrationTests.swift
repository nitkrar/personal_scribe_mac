import XCTest

@testable import PersonalScribeCore
@testable import PersonalScribeSession
import PersonalScribeTestSupport
@testable import PersonalScribeVAD

final class VadOrchestratorIntegrationTests: XCTestCase {

    func testRecordingModeAsksVadProviderAndFiresHandlerOnSpeechEnded() async throws {
        let capture = FakeAudioCapturing(
            buffers: try Self.makeBuffers(count: 3),
            delayPerBuffer: .milliseconds(20)
        )
        let provider = CountingVadProvider(fireOnIngestIndex: 1)
        let prefs = ScriptedVadPreferences(
            value: VadPreferences(autoStopEnabled: true, silenceThresholdSeconds: 2.5)
        )
        let handlerCalls = HandlerCallCounter()
        let orchestrator = makeOrchestrator(
            capture: capture,
            vadProvider: provider,
            vadPreferences: prefs
        )
        // Tests assert on handler invocation + provider query directly. The
        // production handler calls `coordinator.stopIfActive` which transitions
        // the pipeline state; in this orchestrator-level test we skip that
        // side effect and verify the two observable behaviors under test.
        await orchestrator.setAutoStopHandler { await handlerCalls.increment() }

        await orchestrator.toggleCapture()
        try await waitUntil(.seconds(2)) { await handlerCalls.count >= 1 }
        await capture.stop()

        let sessionCount = await provider.makeSessionCallCount
        XCTAssertEqual(sessionCount, 1, "recording mode should request exactly one VAD session")
        let callCount = await handlerCalls.count
        XCTAssertEqual(callCount, 1, "onAutoStopRequested should fire exactly once per session")
    }

    func testHoldRecordingSkipsVadEntirely() async throws {
        let capture = FakeAudioCapturing(
            buffers: try Self.makeBuffers(count: 3),
            delayPerBuffer: .milliseconds(10)
        )
        let provider = CountingVadProvider(fireOnIngestIndex: 0)
        let prefs = ScriptedVadPreferences(
            value: VadPreferences(autoStopEnabled: true, silenceThresholdSeconds: 2.5)
        )
        let handlerCalls = HandlerCallCounter()
        let orchestrator = makeOrchestrator(
            capture: capture,
            vadProvider: provider,
            vadPreferences: prefs
        )
        await orchestrator.setAutoStopHandler { await handlerCalls.increment() }

        await orchestrator.startHoldCapture()
        try await Task.sleep(for: .milliseconds(100))
        await capture.stop()

        let sessionCount = await provider.makeSessionCallCount
        XCTAssertEqual(sessionCount, 0, "hold mode must not ask the provider for a session")
        let callCount = await handlerCalls.count
        XCTAssertEqual(callCount, 0, "hold mode must not fire the auto-stop handler")
    }

    func testAutoStopHandlerCallingPipelineToggleCaptureDoesNotSelfDeadlock() async throws {
        // Regression catch for the codex-flagged deadlock: if
        // `consumeCaptureStream` ever reverts to inline-awaiting the handler,
        // the handler's `pipeline.toggleCapture` call will hit
        // `stopRecordingAndRunPipeline`'s `await captureTask?.value`, which is
        // the task currently running the consumer loop — self-wait → deadlock.
        //
        // This test installs a handler that invokes the real pipeline stop
        // path (NOT just a counter). If the detached-Task escape in
        // consumeCaptureStream is intact, the session transitions out of
        // `.recording` within the deadline. If it regresses to inline-await,
        // the session is stuck and the deadline fires.
        let capture = FakeAudioCapturing(
            buffers: try Self.makeBuffers(count: 3),
            delayPerBuffer: .milliseconds(20)
        )
        let provider = CountingVadProvider(fireOnIngestIndex: 1)
        let prefs = ScriptedVadPreferences(
            value: VadPreferences(autoStopEnabled: true, silenceThresholdSeconds: 2.5)
        )
        let orchestrator = makeOrchestrator(
            capture: capture,
            vadProvider: provider,
            vadPreferences: prefs
        )
        await orchestrator.setAutoStopHandler { [weak orchestrator] in
            await orchestrator?.toggleCapture()
        }

        await orchestrator.toggleCapture()
        try await waitUntil(.seconds(3)) {
            let state = await orchestrator.snapshot().sessionState
            return state != .recording && state != .idle
        }
    }

    func testDisabledPreferenceSkipsVadEntirely() async throws {
        let capture = FakeAudioCapturing(
            buffers: try Self.makeBuffers(count: 3),
            delayPerBuffer: .milliseconds(10)
        )
        let provider = CountingVadProvider(fireOnIngestIndex: 0)
        let prefs = ScriptedVadPreferences(
            value: VadPreferences(autoStopEnabled: false, silenceThresholdSeconds: 2.5)
        )
        let handlerCalls = HandlerCallCounter()
        let orchestrator = makeOrchestrator(
            capture: capture,
            vadProvider: provider,
            vadPreferences: prefs
        )
        await orchestrator.setAutoStopHandler { await handlerCalls.increment() }

        await orchestrator.toggleCapture()
        try await Task.sleep(for: .milliseconds(100))
        await capture.stop()

        let sessionCount = await provider.makeSessionCallCount
        XCTAssertEqual(sessionCount, 0, "disabled preference must short-circuit before provider call")
        let callCount = await handlerCalls.count
        XCTAssertEqual(callCount, 0, "disabled preference must not fire the handler")
    }

    // MARK: - Helpers

    private func makeOrchestrator(
        capture: any AudioCapturing,
        vadProvider: any VadProviding,
        vadPreferences: any VadPreferencesReading
    ) -> SessionPipelineOrchestrator {
        SessionPipelineOrchestrator(
            capture: capture,
            transcriber: FakeTranscriber(
                result: TranscriptionResult(
                    text: "",
                    audioDuration: .seconds(1),
                    processingDuration: .zero
                )
            ),
            logger: PersonalScribeLogger(category: PersonalScribeLogCategory.session),
            outputSink: TestPipelineOutputSink(),
            contextProvider: StaticPipelineContextProvider(
                context: PipelineContextSnapshot(streamingOutputEnabled: false)
            ),
            vadProvider: vadProvider,
            vadPreferences: vadPreferences
        )
    }

    private func waitUntil(
        _ timeout: Duration,
        predicate: @escaping @Sendable () async -> Bool
    ) async throws {
        let deadline = ContinuousClock().now + timeout
        while ContinuousClock().now < deadline {
            if await predicate() { return }
            try await Task.sleep(for: .milliseconds(15))
        }
        XCTFail("Predicate did not become true within \(timeout)")
    }

    private static func makeBuffers(count: Int) throws -> [PCMBuffer] {
        try (0..<count).map { _ in
            try PCMBuffer(
                samples: Array(repeating: Float(0), count: 1600),
                timestamp: ContinuousClock().now
            )
        }
    }
}

// MARK: - Test fakes

private actor CountingVadProvider: VadProviding {
    private(set) var makeSessionCallCount = 0
    private let fireOnIngestIndex: Int

    init(fireOnIngestIndex: Int) {
        self.fireOnIngestIndex = fireOnIngestIndex
    }

    func makeSession(silenceThresholdSeconds: Double) async -> VadSessionHandle? {
        makeSessionCallCount += 1
        let counter = IngestCounter()
        let fireIndex = fireOnIngestIndex
        return VadSessionHandle { _ in
            let idx = await counter.next()
            return idx == fireIndex ? .speechEnded : nil
        }
    }
}

private actor IngestCounter {
    private var idx = 0
    func next() -> Int {
        defer { idx += 1 }
        return idx
    }
}

private actor HandlerCallCounter {
    private(set) var count = 0
    func increment() { count += 1 }
}

private struct ScriptedVadPreferences: VadPreferencesReading {
    let value: VadPreferences
    func current() -> VadPreferences { value }
}

private struct StaticPipelineContextProvider: PipelineContextProviding {
    let context: PipelineContextSnapshot
    func currentContext() -> PipelineContextSnapshot { context }
}

private actor TestPipelineOutputSink: PipelineOutputSink {
    func deliverPartial(_ revision: TranscriptProgress) async throws {}
    func deliverFinal(_ result: TranscriptionResult) async throws {}
    func resetForNewSession() async {}
}
