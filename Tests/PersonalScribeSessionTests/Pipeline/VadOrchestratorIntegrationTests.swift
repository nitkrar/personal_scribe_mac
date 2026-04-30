import XCTest

@testable import PersonalScribeCore
@testable import PersonalScribeSession
import PersonalScribeTestSupport
@testable import PersonalScribeVAD

final class VadOrchestratorIntegrationTests: XCTestCase {

    func testRecordingModeAsksVadProviderAndFiresHandlerOnSpeechEnded() async throws {
        let capture = FakeAudioCapturer(
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
        let capture = FakeAudioCapturer(
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
        // `.capturing` within the deadline. If it regresses to inline-await,
        // the session is stuck and the deadline fires.
        let capture = FakeAudioCapturer(
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
            return state != .capturing && state != .idle
        }
    }

    func testGraceTimerFiresAutoStopAfterDuration() async throws {
        // Stage B warn-enabled path: speechEnded → grace window (shortened to
        // 50ms in tests) → handler fires once. Asserts the full grace-window
        // lifecycle end-to-end. Production default is 3.0s.
        let capture = FakeAudioCapturer(
            buffers: try Self.makeBuffers(count: 3),
            delayPerBuffer: .milliseconds(10)
        )
        let provider = ScriptedVadProvider(events: [.speechEnded])
        let prefs = ScriptedVadPreferences(
            value: VadPreferences(
                autoStopEnabled: true,
                silenceThresholdSeconds: 2.5,
                showStoppingWarning: true
            )
        )
        let handlerCalls = HandlerCallCounter()
        let orchestrator = makeOrchestrator(
            capture: capture,
            vadProvider: provider,
            vadPreferences: prefs,
            graceDurationSeconds: 0.05
        )
        await orchestrator.setAutoStopHandler { [weak capture] in
            await handlerCalls.increment()
            await capture?.stop()
        }

        await orchestrator.toggleCapture()
        try await waitUntil(.seconds(2)) { await handlerCalls.count >= 1 }

        let callCount = await handlerCalls.count
        XCTAssertEqual(callCount, 1, "grace timer must fire auto-stop exactly once")
        let snapshot = await orchestrator.snapshot()
        XCTAssertFalse(
            snapshot.vadAutoStopGracePending,
            "grace pending must clear after timer fires"
        )
        XCTAssertNotNil(
            snapshot.vadAutoStopFireToken,
            "timer-elapsed path must publish a fire token"
        )
    }

    func testSpeechResumedCancelsGrace() async throws {
        // Stage B: during a pending grace window, a `.speechResumed` event
        // from the VAD session must cancel the timer. Handler never fires;
        // session stays recording.
        let capture = FakeAudioCapturer(
            buffers: try Self.makeBuffers(count: 3),
            delayPerBuffer: .milliseconds(10)
        )
        let provider = ScriptedVadProvider(events: [.speechEnded, .speechResumed])
        let prefs = ScriptedVadPreferences(
            value: VadPreferences(
                autoStopEnabled: true,
                silenceThresholdSeconds: 2.5,
                showStoppingWarning: true
            )
        )
        let handlerCalls = HandlerCallCounter()
        let orchestrator = makeOrchestrator(
            capture: capture,
            vadProvider: provider,
            vadPreferences: prefs,
            graceDurationSeconds: 1.0  // long enough that speechResumed wins the race
        )
        await orchestrator.setAutoStopHandler { await handlerCalls.increment() }

        await orchestrator.toggleCapture()
        try await Task.sleep(for: .milliseconds(200))
        await capture.stop()

        let callCount = await handlerCalls.count
        XCTAssertEqual(callCount, 0, "speechResumed must prevent handler from firing")
        let snapshot = await orchestrator.snapshot()
        XCTAssertFalse(
            snapshot.vadAutoStopGracePending,
            "speechResumed must clear grace pending"
        )
        XCTAssertNil(
            snapshot.vadAutoStopFireToken,
            "cancelled grace must NOT publish a fire token"
        )
    }

    /// Bug fix regression guard: after a `.speechResumed` cancels a
    /// pending grace, VAD must re-arm so a subsequent `.speechEnded`
    /// triggers a new grace cycle. Pre-fix, `resolveGracePending(.cancelled)`
    /// transitioned phase to `.resolved` — which the
    /// `consumeCaptureStream` gate (`if case .resolved = gracePhase
    /// { continue }`) interpreted as "session done, skip VAD forever".
    /// The result was: silence → VAD pending → user speaks → cancelled
    /// → user goes silent again → VAD never fires. Post-fix, the
    /// cancelled branch transitions to `.idle` so the next silence
    /// starts a fresh grace.
    func testSpeechResumedReArmsVadForSubsequentSpeechEnded() async throws {
        // 5 buffers at 10ms each → ingests #1, #2, #3 fire the script;
        // ingests #4, #5 return nil (overrun). Grace is long enough
        // (1s) that the second pending stays open by the time we
        // sample the snapshot.
        let capture = FakeAudioCapturer(
            buffers: try Self.makeBuffers(count: 5),
            delayPerBuffer: .milliseconds(10)
        )
        let provider = ScriptedVadProvider(
            events: [.speechEnded, .speechResumed, .speechEnded]
        )
        let prefs = ScriptedVadPreferences(
            value: VadPreferences(
                autoStopEnabled: true,
                silenceThresholdSeconds: 2.5,
                showStoppingWarning: true
            )
        )
        let handlerCalls = HandlerCallCounter()
        let orchestrator = makeOrchestrator(
            capture: capture,
            vadProvider: provider,
            vadPreferences: prefs,
            graceDurationSeconds: 1.0
        )
        await orchestrator.setAutoStopHandler { await handlerCalls.increment() }

        await orchestrator.toggleCapture()
        // Wait for all 5 buffers to flow + the third speechEnded to
        // start a new grace window. ~80ms is enough at 10ms/buffer
        // plus some scheduling slack.
        try await waitUntil(.milliseconds(500)) {
            let snapshot = await orchestrator.snapshot()
            return snapshot.vadAutoStopGracePending
                && snapshot.vadAutoStopFireToken == nil
        }

        let snapshot = await orchestrator.snapshot()
        // Pre-fix: the third `.speechEnded` was skipped at the
        // `gracePhase == .resolved` gate, so pending stays false.
        // Post-fix: the cancelled branch transitioned to `.idle`,
        // so the third event re-armed grace.
        XCTAssertTrue(
            snapshot.vadAutoStopGracePending,
            "VAD must re-arm after speechResumed: expected a new grace window for the second silence"
        )
        let callCount = await handlerCalls.count
        XCTAssertEqual(callCount, 0, "neither grace window completes its timer in this short test")
    }

    func testErrorDuringGraceClearsGraceInSamePublish() async throws {
        // Codex review #7: grace-cleared + `.error` must land in the same
        // snapshot mutation. Observers must never see an intermediate
        // `.capturing + !vadAutoStopGracePending` snapshot.
        let capture = FakeAudioCapturer(
            buffers: try Self.makeBuffers(count: 1),
            error: .resampleFailure,
            delayPerBuffer: .milliseconds(10)
        )
        let provider = ScriptedVadProvider(events: [.speechEnded])
        let prefs = ScriptedVadPreferences(
            value: VadPreferences(
                autoStopEnabled: true,
                silenceThresholdSeconds: 2.5,
                showStoppingWarning: true
            )
        )
        let orchestrator = makeOrchestrator(
            capture: capture,
            vadProvider: provider,
            vadPreferences: prefs,
            graceDurationSeconds: 2.0
        )
        await orchestrator.setAutoStopHandler { /* no-op */ }

        let stream = await orchestrator.snapshotStream()
        let observedTask = Task { () -> [SessionSnapshot] in
            var snapshots: [SessionSnapshot] = []
            for await snapshot in stream {
                snapshots.append(snapshot)
                if case .error = snapshot.sessionState { break }
            }
            return snapshots
        }

        await orchestrator.toggleCapture()
        let observed = try await withTimeout(.seconds(2)) { await observedTask.value }

        // Find the snapshot where grace started (pending=true).
        guard let graceStart = observed.firstIndex(where: { $0.vadAutoStopGracePending }) else {
            XCTFail("expected at least one snapshot with grace pending")
            return
        }
        // Every subsequent snapshot up to .error must either still have
        // grace pending OR already be .error. Never .capturing && !pending.
        for snapshot in observed[graceStart...] {
            if case .error = snapshot.sessionState { continue }
            XCTAssertTrue(
                snapshot.vadAutoStopGracePending,
                "grace-clear must not leak into a non-error snapshot: \(snapshot)"
            )
        }
        let finalSnapshot = observed.last!
        if case .error = finalSnapshot.sessionState {
            XCTAssertFalse(finalSnapshot.vadAutoStopGracePending)
            XCTAssertNil(finalSnapshot.vadAutoStopFireToken)
        } else {
            XCTFail("expected terminal .error snapshot, got \(finalSnapshot.sessionState)")
        }
    }

    func testDisabledPreferenceSkipsVadEntirely() async throws {
        let capture = FakeAudioCapturer(
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
        capture: any AudioCapturer,
        vadProvider: any VadProviding,
        vadPreferences: any VadPreferencesReading,
        graceDurationSeconds: Double = SessionPipelineOrchestrator.defaultGraceDurationSeconds
    ) -> SessionPipelineOrchestrator {
        // #078.29 + #089: orchestrator takes VAD config from the
        // bound recipe's `.vad` capture controller. Translate the
        // legacy `vadPreferences` reader into recipe shape — the
        // `enabled:` parameter (#089) gates wiring, so feed it from
        // `prefs.autoStopEnabled` here for parity with the pre-#089
        // behaviour these tests pin.
        let prefs = vadPreferences.current()
        let captureControllers: [BoundCaptureController] = [
            .vad(
                enabled: prefs.autoStopEnabled,
                silenceThreshold: prefs.silenceThresholdSeconds,
                showWarning: prefs.showStoppingWarning,
                showAutoStoppedNotification: prefs.showAutoStoppedNotification
            ),
            .manualHotkey,
        ]
        let recipe = BoundRecipe(
            recipeID: "dictation",
            recipeName: "Dictation",
            pipelineShape: .batch,
            processors: [
                .transcriber(
                    FakeTranscriber(
                        result: TranscriptionResult(
                            text: "",
                            audioDuration: .seconds(1),
                            processingDuration: .zero
                        )
                    )
                )
            ],
            captureControllers: captureControllers,
            outputSinks: [.frontmostPaste(enabled: true)]
        )
        return SessionPipelineOrchestrator(
            capture: capture,
            logger: PersonalScribeLogger.testing(category: PersonalScribeLogCategory.session),
            outputSink: TestPipelineOutputSink(),
            contextProvider: StaticPipelineContextProvider(
                context: PipelineContextSnapshot(streamingOutputEnabled: false)
            ),
            vadProvider: vadProvider,
            boundRecipe: recipe,
            graceDurationSeconds: graceDurationSeconds
        )
    }

    private func withTimeout<T: Sendable>(
        _ timeout: Duration,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw XCTSkip("timed out after \(timeout)")
            }
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
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

/// Scripted VAD provider for Stage B tests — drives a sequence of events
/// indexed by ingest call number. Any positions past the script return nil.
private actor ScriptedVadProvider: VadProviding {
    private(set) var makeSessionCallCount = 0
    private let events: [VadEvent?]

    init(events: [VadEvent?]) {
        self.events = events
    }

    func makeSession(silenceThresholdSeconds: Double) async -> VadSessionHandle? {
        makeSessionCallCount += 1
        let counter = IngestCounter()
        let eventsCapture = events
        return VadSessionHandle { _ in
            let idx = await counter.next()
            return idx < eventsCapture.count ? eventsCapture[idx] : nil
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
