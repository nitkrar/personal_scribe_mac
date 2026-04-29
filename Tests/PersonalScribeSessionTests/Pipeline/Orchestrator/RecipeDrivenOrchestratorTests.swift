import XCTest

@testable import PersonalScribeCore
@testable import PersonalScribeSession
import PersonalScribeTestSupport
@testable import PersonalScribeVAD

/// #078.29 — `SessionPipelineOrchestrator` consumes a `BoundRecipe` at
/// session start. The recipe drives:
/// - VAD wiring (presence of `.vad` capture controller plus the
///   eager-resolved silence threshold + warning + notification flags).
/// - Per-processor dispatch via `BoundProcessor` cases (`.transcriber`,
///   `.streamingTranscriber`, `.diarizedTurns`).
///
/// Tests cover the dispatch + wiring invariants. The mid-session
/// no-effect guarantee is implicit in the `BoundRecipe` immutability
/// (proven directly by `RecipeBuilderTests`); orchestrator-level
/// regression guards live here.
final class RecipeDrivenOrchestratorTests: XCTestCase {

    // MARK: - Wiring: VAD capture controller

    /// When the bound recipe declares a `.vad` capture controller, the
    /// orchestrator asks the VAD provider for a session at start —
    /// exercising the same VAD lifecycle as the legacy `vadPreferences`
    /// path.
    func testOrchestratorWiresVadCaptureControllerWhenInRecipe() async throws {
        let capture = FakeAudioCapturer(
            buffers: try Self.makeBuffers(count: 3),
            delayPerBuffer: .milliseconds(20)
        )
        let provider = CountingVadProvider(fireOnIngestIndex: 1)
        let recipe = BoundRecipe(
            recipeID: "recipe-with-vad",
            recipeName: "Recipe With VAD",
            pipelineShape: .batch,
            processors: [.transcriber(StubBoundTranscriber())],
            captureControllers: [
                .vad(
                    enabled: true,
                    silenceThreshold: 2.5,
                    showWarning: false,
                    showAutoStoppedNotification: false
                ),
                .manualHotkey,
            ],
            outputSinks: [.frontmostPaste(enabled: true)]
        )

        let handlerCalls = HandlerCallCounter()
        let orchestrator = makeOrchestrator(
            capture: capture,
            vadProvider: provider,
            boundRecipe: recipe
        )
        await orchestrator.setAutoStopHandler { await handlerCalls.increment() }

        await orchestrator.toggleCapture()
        try await waitUntil(.seconds(2)) { await handlerCalls.count >= 1 }
        await capture.stop()

        let sessionCount = await provider.makeSessionCallCount
        XCTAssertEqual(
            sessionCount, 1,
            "recipe with .vad must request exactly one VAD session"
        )
        let callCount = await handlerCalls.count
        XCTAssertEqual(
            callCount, 1,
            "VAD-driven auto-stop handler must fire exactly once"
        )
    }

    /// H.5 (#089) — when the bound recipe declares `.vad(enabled:
    /// false, ...)`, the orchestrator must skip VAD wiring entirely
    /// even though the controller is present in the recipe. Pins the
    /// new `enabled` parameter as the gate.
    func testVadEnabledFalseSkipsWiring() async throws {
        let capture = FakeAudioCapturer(
            buffers: try Self.makeBuffers(count: 3),
            delayPerBuffer: .milliseconds(10)
        )
        let provider = CountingVadProvider(fireOnIngestIndex: 0)
        let recipe = BoundRecipe(
            recipeID: "vad-disabled",
            recipeName: "VAD disabled",
            pipelineShape: .batch,
            processors: [.transcriber(StubBoundTranscriber())],
            captureControllers: [
                .vad(
                    enabled: false,
                    silenceThreshold: 2.5,
                    showWarning: false,
                    showAutoStoppedNotification: false
                ),
                .manualHotkey,
            ],
            outputSinks: [.frontmostPaste(enabled: true)]
        )
        let handlerCalls = HandlerCallCounter()
        let orchestrator = makeOrchestrator(
            capture: capture,
            vadProvider: provider,
            boundRecipe: recipe
        )
        await orchestrator.setAutoStopHandler { await handlerCalls.increment() }

        await orchestrator.toggleCapture()
        try await Task.sleep(for: .milliseconds(150))
        await capture.stop()

        let sessionCount = await provider.makeSessionCallCount
        XCTAssertEqual(
            sessionCount, 0,
            "`.vad(enabled: false)` must NOT request a VAD session"
        )
        let callCount = await handlerCalls.count
        XCTAssertEqual(
            callCount, 0,
            "`.vad(enabled: false)` must not fire the auto-stop handler"
        )
    }

    /// When the bound recipe has NO `.vad` capture controller, the
    /// orchestrator must NEVER ask the VAD provider for a session,
    /// even if `vadProvider` and a VAD-enabled `vadPreferences` are
    /// wired (legacy preference path is suppressed when a recipe is
    /// present).
    func testOrchestratorOmitsVadWhenAbsentFromRecipe() async throws {
        let capture = FakeAudioCapturer(
            buffers: try Self.makeBuffers(count: 3),
            delayPerBuffer: .milliseconds(10)
        )
        let provider = CountingVadProvider(fireOnIngestIndex: 0)
        let recipe = BoundRecipe(
            recipeID: "manual-only",
            recipeName: "Manual only",
            pipelineShape: .batch,
            processors: [.transcriber(StubBoundTranscriber())],
            captureControllers: [.manualHotkey],
            outputSinks: [.frontmostPaste(enabled: true)]
        )
        // Provide a legacy `vadPreferences` with autoStopEnabled=true to
        // prove the recipe wins: the recipe has no .vad, so VAD must
        // not fire even though the legacy reader says it's enabled.
        let prefs = ScriptedVadPreferences(
            value: VadPreferences(autoStopEnabled: true, silenceThresholdSeconds: 2.5)
        )
        let handlerCalls = HandlerCallCounter()
        let orchestrator = makeOrchestrator(
            capture: capture,
            vadProvider: provider,
            vadPreferences: prefs,
            boundRecipe: recipe
        )
        await orchestrator.setAutoStopHandler { await handlerCalls.increment() }

        await orchestrator.toggleCapture()
        try await Task.sleep(for: .milliseconds(150))
        await capture.stop()

        let sessionCount = await provider.makeSessionCallCount
        XCTAssertEqual(
            sessionCount, 0,
            "recipe without .vad must NOT request a VAD session"
        )
        let callCount = await handlerCalls.count
        XCTAssertEqual(
            callCount, 0,
            "no VAD in recipe → handler never fires"
        )
    }

    // MARK: - Dispatch: ProcessorOutput sum-type cases

    /// `BoundProcessor.transcriber(...)` runs the bound `Transcriber`
    /// adapter on the buffered audio; the orchestrator dispatches the
    /// `.text(TranscriptionResult)` case into the legacy post-process /
    /// persist / output path.
    func testOrchestratorDispatchesProcessorOutputBySumTypeCase() async throws {
        let buffer = try Self.makeBuffer(sampleCount: 16_000)
        let stubTranscriber = StubBoundTranscriber(
            result: TranscriptionResult(
                text: "recipe path hello",
                audioDuration: .seconds(1),
                processingDuration: .milliseconds(200)
            )
        )
        let recipe = BoundRecipe(
            recipeID: "dictation",
            recipeName: "Dictation",
            pipelineShape: .batch,
            processors: [.transcriber(stubTranscriber)],
            captureControllers: [.manualHotkey],
            outputSinks: [.frontmostPaste(enabled: true)]
        )
        let sink = TestPipelineOutputSink()
        let orchestrator = makeOrchestrator(
            capture: FakeAudioCapturer(buffers: [buffer]),
            outputSink: sink,
            boundRecipe: recipe
        )

        await orchestrator.toggleCapture()
        await orchestrator.toggleCapture()
        try await waitUntil(.seconds(2)) {
            let snapshot = await orchestrator.snapshot()
            return snapshot.lastCompletedResult != nil
        }

        let snapshot = await orchestrator.snapshot()
        XCTAssertEqual(snapshot.sessionState, .completed)
        XCTAssertEqual(
            snapshot.lastCompletedResult?.text,
            "Recipe path hello.",
            "BoundProcessor.transcriber output must flow through post-processing"
        )

        // Bound transcriber's `transcribe(_:)` method was called.
        let callCount = await stubTranscriber.transcribeCallCount()
        XCTAssertEqual(
            callCount, 1,
            "BoundProcessor.transcriber dispatch must call the bound adapter"
        )

        let finals = await sink.finalDeliveries()
        XCTAssertEqual(finals.count, 1, "final result must flow to the output sink")
    }

    /// `BoundProcessor.diarizedTurns(...)` routes through the fusion
    /// processor (`DiarizedTurnTranscriptionProcessor`): the diarizer
    /// emits a terminal turn, the per-turn transcriber runs, the
    /// orchestrator dispatches the resulting `.text` case.
    func testOrchestratorRoutesDiarizedRecipeThroughFusionProcessor() async throws {
        let buffer = try Self.makeBuffer(sampleCount: 16_000)
        let diarizer = StubBoundDiarizer(
            terminalTurns: [
                SpeakerTurn(
                    speakerID: "spk1",
                    start: .zero,
                    end: .seconds(1)
                ),
            ]
        )
        let perTurnTranscriber = StubBoundTranscriber(
            result: TranscriptionResult(
                text: "turn one",
                audioDuration: .seconds(1),
                processingDuration: .zero
            )
        )
        let recipe = BoundRecipe(
            recipeID: "meeting",
            recipeName: "Meeting",
            pipelineShape: .batch,
            processors: [.diarizedTurns(diarizer: diarizer, transcriber: perTurnTranscriber)],
            captureControllers: [.manualHotkey],
            outputSinks: [.frontmostPaste(enabled: true)]
        )
        let orchestrator = makeOrchestrator(
            capture: FakeAudioCapturer(buffers: [buffer]),
            boundRecipe: recipe
        )

        await orchestrator.toggleCapture()
        await orchestrator.toggleCapture()
        try await waitUntil(.seconds(2)) {
            let snapshot = await orchestrator.snapshot()
            return snapshot.lastCompletedResult != nil
        }

        let snapshot = await orchestrator.snapshot()
        XCTAssertEqual(snapshot.sessionState, .completed)
        XCTAssertEqual(
            snapshot.lastCompletedResult?.text,
            "Speaker 1: turn one.",
            "Diarized recipe must flow speaker-prefixed turn transcripts into post-processing"
        )
        let perTurnCalls = await perTurnTranscriber.transcribeCallCount()
        XCTAssertEqual(
            perTurnCalls, 1,
            "Fusion processor must invoke the per-turn transcriber once for the single turn"
        )
    }

    // MARK: - Builds at session start

    /// The orchestrator binds the recipe at session start (per L25):
    /// the `BoundRecipe` is captured once and used end-to-end for the
    /// session.
    func testOrchestratorBuildsRecipeAtSessionStart() async throws {
        let buffer = try Self.makeBuffer(sampleCount: 16_000)
        let stubTranscriber = StubBoundTranscriber(
            result: TranscriptionResult(
                text: "ok",
                audioDuration: .seconds(1),
                processingDuration: .zero
            )
        )
        let recipe = BoundRecipe(
            recipeID: "dictation",
            recipeName: "Dictation",
            pipelineShape: .batch,
            processors: [.transcriber(stubTranscriber)],
            captureControllers: [.manualHotkey],
            outputSinks: [.frontmostPaste(enabled: true)]
        )
        let orchestrator = makeOrchestrator(
            capture: FakeAudioCapturer(buffers: [buffer]),
            boundRecipe: recipe
        )

        await orchestrator.toggleCapture()
        await orchestrator.toggleCapture()
        try await waitUntil(.seconds(2)) {
            let snapshot = await orchestrator.snapshot()
            return snapshot.lastCompletedResult != nil
        }

        let snapshot = await orchestrator.snapshot()
        XCTAssertEqual(snapshot.sessionState, .completed)
        XCTAssertEqual(snapshot.lastCompletedResult?.text, "Ok.")
    }

    // MARK: - Helpers

    private func makeOrchestrator(
        capture: any AudioCapturer = FakeAudioCapturer(),
        outputSink: any PipelineOutputSink = TestPipelineOutputSink(),
        vadProvider: (any VadProviding)? = nil,
        vadPreferences: (any VadPreferencesReading)? = nil,
        boundRecipe: BoundRecipe? = nil,
        graceDurationSeconds: Double = SessionPipelineOrchestrator.defaultGraceDurationSeconds
    ) -> SessionPipelineOrchestrator {
        // #078.29: orchestrator init dropped `transcriber:` and
        // `vadPreferences:` — recipe carries both. The legacy fallback
        // `vadPreferences` arg here stays for symmetry but is ignored
        // post-cutover.
        _ = vadPreferences
        return SessionPipelineOrchestrator(
            capture: capture,
            logger: PersonalScribeLogger(category: PersonalScribeLogCategory.session),
            outputSink: outputSink,
            contextProvider: StaticPipelineContextProvider(
                context: PipelineContextSnapshot(streamingOutputEnabled: false)
            ),
            vadProvider: vadProvider,
            boundRecipe: boundRecipe,
            graceDurationSeconds: graceDurationSeconds
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

    private static func makeBuffer(sampleCount: Int) throws -> PCMBuffer {
        try PCMBuffer(
            samples: Array(repeating: Float(0), count: sampleCount),
            timestamp: ContinuousClock().now
        )
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

// MARK: - Test stubs

private actor StubBoundTranscriber: Transcriber {
    nonisolated let capabilities = TranscriberCapabilities()
    private let result: TranscriptionResult
    private var calls = 0

    init(
        result: TranscriptionResult = TranscriptionResult(
            text: "",
            audioDuration: .zero,
            processingDuration: .zero
        )
    ) {
        self.result = result
    }

    func prepare() async throws {}

    nonisolated func modelDownloadProgress() -> AsyncStream<ModelDownloadProgress> {
        AsyncStream { $0.finish() }
    }

    func transcribe(_ audio: PCMBuffer) async throws -> TranscriptionResult {
        calls += 1
        return result
    }

    func transcribeCallCount() -> Int {
        calls
    }
}

private actor StubBoundDiarizer: SpeakerDiarizer {
    private let terminalTurns: [SpeakerTurn]

    init(terminalTurns: [SpeakerTurn]) {
        self.terminalTurns = terminalTurns
    }

    func prepare() async throws {}

    nonisolated func modelDownloadProgress() -> AsyncStream<ModelDownloadProgress> {
        AsyncStream { $0.finish() }
    }

    nonisolated func diarize(
        stream: AsyncThrowingStream<PCMBuffer, Error>
    ) -> AsyncStream<SpeakerDiarizationEvent> {
        let turns = terminalTurns
        return AsyncStream { continuation in
            Task {
                // Drain the input stream so the producer doesn't block.
                for try await _ in stream {}
                continuation.yield(.terminal(turns))
                continuation.finish()
            }
        }
    }
}

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
    private var partials: [TranscriptProgress] = []
    private var finals: [TranscriptionResult] = []

    func deliverPartial(_ revision: TranscriptProgress) async throws {
        partials.append(revision)
    }

    func deliverFinal(_ result: TranscriptionResult) async throws {
        finals.append(result)
    }

    func resetForNewSession() async {
        partials.removeAll()
        finals.removeAll()
    }

    func partialDeliveries() -> [TranscriptProgress] { partials }
    func finalDeliveries() -> [TranscriptionResult] { finals }
}
