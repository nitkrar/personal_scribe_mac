import Foundation
import os.signpost
import PersonalScribeCore
import PersonalScribeVAD

public actor SessionCoordinator {
    private let capture: any AudioCapturer
    /// #078.31a — fixed recipe used by the test-init path. Production
    /// callers leave this nil and supply `processorProvider` +
    /// `workflowModeRegistry` instead.
    private let fixedRecipe: BoundRecipe?
    private let modelService: ActiveModelService?
    /// #078.31a — typed-accessor processor provider (replaces legacy
    /// `transcriberProvider`). Used together with `workflowModeRegistry`
    /// to build a `BoundRecipe` per session via `RecipeBuilder`.
    private let processorProvider: (any ModelBoundProcessorProviding)?
    private let transcriptRepository: TranscriptRepository?
    private let logger: PersonalScribeLogger
    private let signposter = OSSignposter(subsystem: PersonalScribeLogger.subsystem, category: "prepare")
    private let pipeline: SessionPipelineOrchestrator
    /// #078.28 — optional registry for re-validating the active recipe
    /// at session start. Nil for legacy callers that don't yet wire the
    /// recipe-driven path; in that case validation is skipped.
    private let workflowModeRegistry: WorkflowModeRegistry?
    /// Snapshot of currently-available `ModelKind` values for recipe
    /// validation. Called once per `startIfIdle`/`startHoldIfIdle`. Nil
    /// when no registry is wired.
    private let availableKindsProvider: (@Sendable () -> Set<ModelKind>)?

    // Step 2.10: additive audio-level multiplexing. Subscribes to the capture
    // service's per-session level stream and fans values out to all
    // registered consumers so SwiftUI surfaces can bind directly without
    // holding a reference to the capture actor. Current value is cached so
    // late subscribers get a starting sample.
    private var audioLevelContinuations: [UUID: AsyncStream<Float>.Continuation] = [:]
    private var currentAudioLevel: Float = 0.0
    private var audioLevelTask: Task<Void, Never>?

    /// Test-only init. Wraps `transcriber` as the asr processor of a
    /// built-in batch dictation recipe and binds that recipe to every
    /// session. Useful for state-machine + orchestrator-flow tests
    /// that don't need to exercise registry + active-model resolution.
    public init(
        capture: any AudioCapturer,
        transcriber: any Transcriber,
        logger: PersonalScribeLogger,
        transcriptRepository: TranscriptRepository? = nil,
        vadProvider: (any VadProviding)? = nil,
        workflowModeRegistry: WorkflowModeRegistry? = nil,
        availableKindsProvider: (@Sendable () -> Set<ModelKind>)? = nil
    ) {
        self.capture = capture
        self.fixedRecipe = BoundRecipe(
            recipeID: "dictation",
            recipeName: "Dictation",
            pipelineShape: .batch,
            processors: [.transcriber(transcriber)],
            captureControllers: [.manualHotkey],
            outputSinks: [.frontmostPaste]
        )
        self.modelService = nil
        self.processorProvider = nil
        self.transcriptRepository = transcriptRepository
        self.logger = logger
        self.workflowModeRegistry = workflowModeRegistry
        self.availableKindsProvider = availableKindsProvider
        self.pipeline = Self.makePipeline(
            capture: capture,
            transcriptRepository: transcriptRepository,
            logger: logger,
            vadProvider: vadProvider
        )
        Task { [weak self] in
            await self?.installAutoStopHandler()
        }
    }

    /// Production init. Builds a fresh `BoundRecipe` per session via
    /// `RecipeBuilder` over the supplied registry + active-model state
    /// (per #078.31a "swap provider injection"). Replaces the legacy
    /// `transcriberProvider:` arg.
    public init(
        capture: any AudioCapturer,
        modelService: ActiveModelService,
        processorProvider: any ModelBoundProcessorProviding,
        logger: PersonalScribeLogger,
        transcriptRepository: TranscriptRepository? = nil,
        vadProvider: (any VadProviding)? = nil,
        workflowModeRegistry: WorkflowModeRegistry,
        availableKindsProvider: @escaping @Sendable () -> Set<ModelKind>
    ) {
        self.capture = capture
        self.fixedRecipe = nil
        self.modelService = modelService
        self.processorProvider = processorProvider
        self.transcriptRepository = transcriptRepository
        self.logger = logger
        self.workflowModeRegistry = workflowModeRegistry
        self.availableKindsProvider = availableKindsProvider
        self.pipeline = Self.makePipeline(
            capture: capture,
            transcriptRepository: transcriptRepository,
            logger: logger,
            vadProvider: vadProvider
        )
        Task { [weak self] in
            await self?.installAutoStopHandler()
        }
    }

    /// Installs the VAD auto-stop handler on the pipeline. Fires from a
    /// deferred Task to avoid referencing `self` before init completes. The
    /// handler captures `[weak self]` and routes through `stopIfActive()` so
    /// it's idempotent vs. concurrent manual stops (actor-serialized, first
    /// wins, second observes post-stop state and no-ops).
    private func installAutoStopHandler() async {
        await pipeline.setAutoStopHandler { [weak self] in
            await self?.stopIfActive()
        }
    }

    public func toggle() async {
        switch await currentDisplayState() {
        case .idle:
            await performStart()
        case .capturing, .holdRecording:
            await performStop()
        case .transcribing, .error:
            await performToggle()
        case .completed, .shortExit:
            // Unreachable via `currentDisplayState()` — both map to `.idle`.
            await performStart()
        }
    }

    public func startIfIdle() async {
        guard await currentDisplayState() == .idle else {
            return
        }

        if await !validateActiveRecipeForSessionStart() {
            return
        }

        await performStart()
    }

    /// Enter `.holdRecording` from `.idle`. Routes through the pipeline's
    /// eager-publish `startHoldCapture()` so a concurrent release seen by
    /// `stopIfActive()` observes `.holdRecording` and stops correctly
    /// instead of silently no-opping on `.idle`. No-op from any other
    /// state. See `#071`.
    public func startHoldIfIdle() async {
        guard await currentDisplayState() == .idle else {
            return
        }

        if await !validateActiveRecipeForSessionStart() {
            return
        }

        await performHoldStart()
    }

    public func stopIfRecording() async {
        guard await currentDisplayState() == .capturing else {
            return
        }

        await performStop()
    }

    /// Mode-agnostic stop. Transitions either `.capturing` or
    /// `.holdRecording` into `.transcribing` via the normal pipeline
    /// stop path. Preferred entry point for hold-release, VAD auto-stop
    /// (#046), and app-quit cleanup — those callers don't know or care
    /// how the session started. No-op from `.idle`, `.transcribing`,
    /// or `.error`.
    public func stopIfActive() async {
        switch await currentDisplayState() {
        case .capturing, .holdRecording:
            await performStop()
        case .idle, .completed, .shortExit, .transcribing, .error:
            return
        }
    }

    /// Mode-agnostic true-cancel. Transitions either `.capturing` or
    /// `.holdRecording` directly to `.idle` via `pipeline.cancelCapture()`
    /// — buffered audio is discarded, transcribe + output stages are
    /// skipped entirely. Preferred entry point for Esc and the pill ✕
    /// button (#002). No-op from `.idle`, `.transcribing`, or `.error`.
    public func cancelIfActive() async {
        switch await currentDisplayState() {
        case .capturing, .holdRecording:
            await performCancel()
        case .idle, .completed, .shortExit, .transcribing, .error:
            return
        }
    }

    public func state() async -> SessionState {
        await currentDisplayState()
    }

    public func stateStream() async -> AsyncStream<SessionState> {
        let snapshotStream = await pipeline.snapshotStream()

        return AsyncStream { continuation in
            let bridgeTask = Task {
                var lastYielded: SessionState?

                for await snapshot in snapshotStream {
                    let state = Self.displayState(for: snapshot.sessionState)
                    guard lastYielded != state else {
                        continue
                    }

                    lastYielded = state
                    continuation.yield(state)
                }

                continuation.finish()
            }

            continuation.onTermination = { _ in
                bridgeTask.cancel()
            }
        }
    }

    public func snapshot() async -> SessionSnapshot {
        await pipeline.snapshot()
    }

    public func snapshotStream() async -> AsyncStream<SessionSnapshot> {
        await pipeline.snapshotStream()
    }

    /// Multiplexed audio-level stream (phase-2 step 2.10). Yields the latest
    /// cached level on subscription and every subsequent level republished
    /// from the pipeline while recording is live. Values are normalized
    /// `[0, 1]`. Stream stays open across start/stop cycles.
    public func audioLevelStream() -> AsyncStream<Float> {
        let id = UUID()

        return AsyncStream { continuation in
            continuation.yield(self.currentAudioLevel)
            self.audioLevelContinuations[id] = continuation
            continuation.onTermination = { [self] _ in
                Task {
                    await self.removeAudioLevelContinuation(id: id)
                }
            }
        }
    }

    /// Latest cached audio-level sample for consumers that prefer a pull
    /// model over stream subscription. Matches the `audioLevel` accessor
    /// pattern in the Phase 2 plan's "AppState role" mapping.
    public func audioLevel() -> Float {
        currentAudioLevel
    }

    public func lastResult() async -> TranscriptionResult? {
        await pipeline.snapshot().lastCompletedResult
    }

    /// Idempotent passthrough for eager model preparation; each
    /// processor's `prepare()` coalesces repeat calls. Builds a recipe
    /// from the current active mode and binds it before delegating to
    /// the pipeline so the recipe path observes the right processor.
    public func prepareTranscriber() async throws {
        let intervalName: StaticString = "SessionCoordinator.prepareTranscriber"
        let state = signposter.beginInterval(intervalName)
        defer { signposter.endInterval(intervalName, state) }
        guard let recipe = try await resolveRecipe() else {
            return
        }
        await pipeline.bindRecipeForNextSession(recipe)
        try await pipeline.prepareTranscriber()
    }

    /// #078.29: orchestrator no longer surfaces a top-level
    /// `modelDownloadProgress()` — progress lands on
    /// `snapshot.modelDownloadProgress` and the snapshot stream
    /// carries it. This bridge exposes the same stream shape for any
    /// caller that prefers a typed progress AsyncStream.
    public func modelDownloadProgress() async -> AsyncStream<ModelDownloadProgress> {
        let snapshotStream = await pipeline.snapshotStream()
        return AsyncStream { continuation in
            let bridgeTask = Task {
                for await snapshot in snapshotStream {
                    if Task.isCancelled { return }
                    if let progress = snapshot.modelDownloadProgress {
                        continuation.yield(progress)
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in
                bridgeTask.cancel()
            }
        }
    }

    private func removeAudioLevelContinuation(id: UUID) {
        audioLevelContinuations[id] = nil
    }

    /// #078.28 — re-validate the registry's active recipe against the
    /// currently-available `ModelKind` set right before starting a
    /// session (per L15). Returns `true` to proceed; `false` after
    /// publishing `.invalidActiveMode` to abort. When no registry is
    /// wired (legacy callers) the check is a no-op pass-through.
    private func validateActiveRecipeForSessionStart() async -> Bool {
        guard let registry = workflowModeRegistry else {
            return true
        }
        let availableKinds = availableKindsProvider?() ?? Set(ModelKind.allCases)
        do {
            _ = try registry.validateActiveForSessionStart(availableKinds: availableKinds)
            return true
        } catch {
            logger.error("Active workflow mode failed validation at session start", error: error)
            await pipeline.publishSessionStartError(.invalidActiveMode)
            return false
        }
    }

    private func performStart() async {
        await bindRecipeBeforeStart()
        await performToggle()
    }

    private func performStop() async {
        await performToggle()
    }

    private func performToggle() async {
        await startAudioLevelRelayIfNeeded()
        await pipeline.toggleCapture()
    }

    private func performHoldStart() async {
        await bindRecipeBeforeStart()
        await startAudioLevelRelayIfNeeded()
        await pipeline.startHoldCapture()
    }

    private func performCancel() async {
        await pipeline.cancelCapture()
    }

    /// Build + bind the recipe for this session per #078.29's
    /// "WorkflowModeRegistry.activeMode() is read once at session
    /// start." On build failure publishes `.invalidActiveMode` so
    /// observers see the same error shape as the L15 validation path.
    private func bindRecipeBeforeStart() async {
        let recipe: BoundRecipe?
        do {
            recipe = try await resolveRecipe()
        } catch {
            logger.error("Failed to build session recipe", error: error)
            await pipeline.publishSessionStartError(.invalidActiveMode)
            return
        }
        guard let recipe else { return }
        await pipeline.bindRecipeForNextSession(recipe)
    }

    /// Resolve the recipe to bind: either the test-only fixed recipe,
    /// or build via `RecipeBuilder` against the current active mode.
    /// Returns nil only when neither path is wired (legacy state).
    private func resolveRecipe() async throws -> BoundRecipe? {
        if let fixedRecipe {
            return fixedRecipe
        }
        guard let registry = workflowModeRegistry,
              let modelService,
              let processorProvider
        else {
            return nil
        }
        return try await MainActor.run {
            let mode = registry.activeMode
            let builder = RecipeBuilder(
                modelService: modelService,
                processorProvider: processorProvider
            )
            return try builder.build(mode)
        }
    }

    private func startAudioLevelRelayIfNeeded() async {
        guard audioLevelTask == nil else {
            return
        }

        // Subscribe before the first recording toggle so the pipeline's cached
        // value and earliest live samples cannot outrun the coordinator relay.
        let stream = await pipeline.audioLevelStream()
        audioLevelTask = Task { [weak self] in
            var didInspectInitialSample = false

            for await level in stream {
                guard let self else {
                    return
                }

                if !didInspectInitialSample {
                    didInspectInitialSample = true
                    if await self.shouldSuppressInitialRelayedAudioLevel(level) {
                        continue
                    }
                }

                await self.publishAudioLevel(level)
            }
        }
    }

    private func shouldSuppressInitialRelayedAudioLevel(_ level: Float) -> Bool {
        level == currentAudioLevel
    }

    private static func makePipeline(
        capture: any AudioCapturer,
        transcriptRepository: TranscriptRepository?,
        logger: PersonalScribeLogger,
        vadProvider: (any VadProviding)?
    ) -> SessionPipelineOrchestrator {
        SessionPipelineOrchestrator(
            capture: capture,
            logger: logger,
            postProcessingPipeline: CoordinatorPostProcessingPipeline(),
            outputSink: CoordinatorPipelineOutputSink(),
            contextProvider: CoordinatorPipelineContextProvider(),
            persistenceHandler: makePersistenceHandler(
                transcriptRepository: transcriptRepository,
                logger: logger
            ),
            vadProvider: vadProvider
        )
    }

    private static func makePersistenceHandler(
        transcriptRepository: TranscriptRepository?,
        logger: PersonalScribeLogger
    ) -> (@Sendable (TranscriptEntry) async throws -> Void)? {
        guard let transcriptRepository else {
            return nil
        }

        return { entry in
            do {
                try await transcriptRepository.append(entry)
            } catch {
                logger.error("Failed to persist transcript to TranscriptRepository", error: error)
            }
        }
    }

    /// Update the cached audio level and fan out to all subscribers.
    private func publishAudioLevel(_ level: Float) {
        currentAudioLevel = level
        for continuation in audioLevelContinuations.values {
            continuation.yield(level)
        }
    }

    private func currentDisplayState() async -> SessionState {
        let snapshot = await pipeline.snapshot()
        return Self.displayState(for: snapshot.sessionState)
    }

    static func displayState(for state: SessionState) -> SessionState {
        switch state {
        case .completed, .shortExit:
            return .idle
        case .idle, .capturing, .holdRecording, .transcribing, .error:
            return state
        }
    }
}

private struct CoordinatorPostProcessingPipeline: PostProcessingPipeline {
    private static let singleWordFillers = try! NSRegularExpression(
        pattern: #"\b(um|uh|uhm|er|erm|ah|ahh|hmm|hmmm|like)\b"#,
        options: [.caseInsensitive]
    )
    private static let hedges = try! NSRegularExpression(
        pattern: #"\b(you know|i mean|i guess|sort of|kind of)\b"#,
        options: [.caseInsensitive]
    )
    private static let repeatedWhitespace = try! NSRegularExpression(
        pattern: #"\s+"#
    )
    private static let leadingPunctuationWhitespace = try! NSRegularExpression(
        pattern: #"\s+([,.!?;:])"#
    )
    private static let trailingPunctuationWhitespace = try! NSRegularExpression(
        pattern: #"([,.!?;:])\s+"#
    )

    func run(_ text: String, context: PostProcessingContext) async throws -> String {
        let stageOne = Self.removeFillers(from: text)
        return Self.applyBasicPunctuation(to: stageOne)
    }

    private static func removeFillers(from raw: String) -> String {
        let withoutSingleWordFillers = singleWordFillers.stringByReplacingMatches(
            in: raw,
            range: NSRange(raw.startIndex..., in: raw),
            withTemplate: " "
        )
        let withoutHedges = hedges.stringByReplacingMatches(
            in: withoutSingleWordFillers,
            range: NSRange(withoutSingleWordFillers.startIndex..., in: withoutSingleWordFillers),
            withTemplate: " "
        )
        let collapsedWhitespace = repeatedWhitespace.stringByReplacingMatches(
            in: withoutHedges,
            range: NSRange(withoutHedges.startIndex..., in: withoutHedges),
            withTemplate: " "
        )
        let trimmedLeadingPunctuationWhitespace = leadingPunctuationWhitespace.stringByReplacingMatches(
            in: collapsedWhitespace,
            range: NSRange(collapsedWhitespace.startIndex..., in: collapsedWhitespace),
            withTemplate: "$1"
        )

        return trailingPunctuationWhitespace.stringByReplacingMatches(
            in: trimmedLeadingPunctuationWhitespace,
            range: NSRange(trimmedLeadingPunctuationWhitespace.startIndex..., in: trimmedLeadingPunctuationWhitespace),
            withTemplate: "$1 "
        )
    }

    private static func applyBasicPunctuation(to text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return ""
        }

        let punctuated: String
        if let lastCharacter = trimmed.last, ".!?".contains(lastCharacter) {
            punctuated = trimmed
        } else {
            punctuated = trimmed + "."
        }

        return punctuated.prefix(1).uppercased() + punctuated.dropFirst()
    }
}

private struct CoordinatorPipelineOutputSink: PipelineOutputSink {
    func deliverPartial(_ revision: TranscriptProgress) async throws {}

    func deliverFinal(_ result: TranscriptionResult) async throws {}

    func resetForNewSession() async {}
}

private struct CoordinatorPipelineContextProvider: PipelineContextProviding {
    func currentContext() -> PipelineContextSnapshot {
        PipelineContextSnapshot(streamingOutputEnabled: false)
    }
}
