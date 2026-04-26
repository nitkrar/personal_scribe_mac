import Foundation
import PersonalScribeCore
import PersonalScribeVAD

public actor SessionPipelineOrchestrator: SessionPipelining {
    private let capture: any AudioCapturer
    private let transcriber: any Transcriber
    private let logger: PersonalScribeLogger
    private let postProcessingPipeline: any PostProcessingPipeline
    private let outputSink: any PipelineOutputSink
    private let contextProvider: any PipelineContextProviding
    private let persistenceHandler: (@Sendable (TranscriptEntry) async throws -> Void)?
    /// VAD provider — nil means the feature is compiled in but not wired (tests)
    /// OR the bundled model failed to load and the provider elected to go silent.
    /// Orchestrator treats either case identically: no VAD monitoring.
    private let vadProvider: (any VadProviding)?
    /// Preference reader called ONCE per session start (in `consumeCaptureStream`).
    /// Mid-session preference changes do not apply to the current recording;
    /// they take effect on the next session. Documented for users in the
    /// Settings card copy.
    private let vadPreferences: (any VadPreferencesReading)?
    /// #078.29 — optional eager-bound recipe (per L25). When present,
    /// the orchestrator drives VAD wiring + processor dispatch off the
    /// recipe; legacy `vadPreferences` and `transcriber` are ignored
    /// for the duration of the session. When nil, the legacy path
    /// runs unchanged. Set once at construction; immutable for the
    /// pipeline's lifetime so mid-session active-mode/active-model
    /// changes never affect an in-flight session.
    private let boundRecipe: BoundRecipe?
    /// Installed by `SessionCoordinator` via `setAutoStopHandler(_:)` after
    /// init. Fires from `consumeCaptureStream` via a detached Task so the
    /// capture consumer can keep draining buffers — inline await would
    /// self-deadlock on `captureTask.value`. See #046 codex design review.
    private var onAutoStopRequested: (@Sendable () async -> Void)?
    /// #046 Stage B: grace-window state machine. Replaces Stage A's loop-
    /// local `vadAlreadyFired` bool so the actor can expose `resolveGrace*`
    /// methods callable from timer-elapsed and cleanup paths.
    private var gracePhase: GracePhase = .idle
    /// Grace-window duration. Production: 3.0s hard-coded per Stage B spec
    /// (bumped from 0.8s on 2026-04-24 after dogfood).
    /// Overridable at init for tests that want to exercise the timer
    /// without sleeping a full grace window.
    private let graceDurationSeconds: Double

    /// Local phase owned by the orchestrator actor. `.pending` carries the
    /// timer task + a UUID token so concurrent timer-fire vs. session-cleanup
    /// paths can safely invalidate each other without double-firing.
    private enum GracePhase: Sendable {
        case idle
        case pending(token: UUID, handler: @Sendable () async -> Void, timerTask: Task<Void, Never>, deadline: Date)
        case resolved
    }

    /// Resolution reason passed to `resolveGracePending`. Drives snapshot
    /// mutations + handler invocation.
    private enum GraceResolveTrigger: Sendable {
        /// Timer elapsed without cancellation. Fires the stop handler and
        /// publishes a fresh `vadAutoStopFireToken` so the notification
        /// path can render.
        case timerElapsed
        /// User resumed speaking OR a cleanup path (manual stop, cancel,
        /// new session) preempted the grace. Clears grace fields; no
        /// fire token; no handler.
        case cancelled
    }

    private var currentSnapshot: SessionSnapshot
    private var activeContext: PipelineContextSnapshot
    private var latestStageFailure: PipelineStageFailure?
    private var snapshotContinuations: [UUID: AsyncStream<SessionSnapshot>.Continuation] = [:]
    private var bufferedAudio: [PCMBuffer] = []
    private var captureTask: Task<Void, Never>?
    private var audioLevelContinuations: [UUID: AsyncStream<Float>.Continuation] = [:]
    private var currentAudioLevel: Float = 0.0
    private var audioLevelTask: Task<Void, Never>?
    private var nextRevision = 0

    public init(
        capture: any AudioCapturer,
        transcriber: any Transcriber,
        transcriptRepository: TranscriptRepository? = nil,
        logger: PersonalScribeLogger,
        postProcessingPipeline: any PostProcessingPipeline = DefaultPostProcessingPipeline(),
        outputSink: any PipelineOutputSink,
        contextProvider: any PipelineContextProviding,
        vadProvider: (any VadProviding)? = nil,
        vadPreferences: (any VadPreferencesReading)? = nil,
        boundRecipe: BoundRecipe? = nil,
        graceDurationSeconds: Double = SessionPipelineOrchestrator.defaultGraceDurationSeconds
    ) {
        let persistenceHandler: (@Sendable (TranscriptEntry) async throws -> Void)?
        if let repository = transcriptRepository {
            persistenceHandler = { (entry: TranscriptEntry) async throws -> Void in
                try await repository.append(entry)
            }
        } else {
            persistenceHandler = nil
        }
        self.init(
            capture: capture,
            transcriber: transcriber,
            logger: logger,
            postProcessingPipeline: postProcessingPipeline,
            outputSink: outputSink,
            contextProvider: contextProvider,
            persistenceHandler: persistenceHandler,
            vadProvider: vadProvider,
            vadPreferences: vadPreferences,
            boundRecipe: boundRecipe,
            graceDurationSeconds: graceDurationSeconds
        )
    }

    init(
        capture: any AudioCapturer,
        transcriber: any Transcriber,
        logger: PersonalScribeLogger,
        postProcessingPipeline: any PostProcessingPipeline,
        outputSink: any PipelineOutputSink,
        contextProvider: any PipelineContextProviding,
        persistenceHandler: (@Sendable (TranscriptEntry) async throws -> Void)?,
        vadProvider: (any VadProviding)? = nil,
        vadPreferences: (any VadPreferencesReading)? = nil,
        boundRecipe: BoundRecipe? = nil,
        graceDurationSeconds: Double = SessionPipelineOrchestrator.defaultGraceDurationSeconds
    ) {
        let initialContext = contextProvider.currentContext()
        self.capture = capture
        self.transcriber = transcriber
        self.logger = logger
        self.postProcessingPipeline = postProcessingPipeline
        self.outputSink = outputSink
        self.contextProvider = contextProvider
        self.persistenceHandler = persistenceHandler
        self.vadProvider = vadProvider
        self.vadPreferences = vadPreferences
        self.boundRecipe = boundRecipe
        self.graceDurationSeconds = graceDurationSeconds
        self.activeContext = initialContext
        self.currentSnapshot = SessionSnapshot()
        Task { [weak self] in
            for await progress in transcriber.modelDownloadProgress() {
                guard let self else {
                    return
                }

                await self.publish { snapshot in
                    snapshot.modelDownloadProgress = Self.normalizeModelDownloadProgress(progress)
                }
            }
        }
    }

    public func toggleCapture() async {
        switch currentSnapshot.sessionState {
        case .idle, .completed, .shortExit:
            await startRecording()
        case .capturing, .holdRecording:
            await stopRecordingAndRunPipeline()
        case .transcribing:
            logger.info("Ignored toggle while transcribing")
        case .error:
            publish { snapshot in
                snapshot.sessionState = .idle
                snapshot.activeStage = nil
                snapshot.transcriptProgress = nil
                snapshot.recordingDuration = nil
            }
            await startRecording()
        }
    }

    public func startHoldCapture() async {
        switch currentSnapshot.sessionState {
        case .idle, .completed, .shortExit:
            await startHoldRecording()
        case .error:
            publish { snapshot in
                snapshot.sessionState = .idle
                snapshot.activeStage = nil
                snapshot.transcriptProgress = nil
                snapshot.recordingDuration = nil
            }
            await startHoldRecording()
        case .capturing, .holdRecording, .transcribing:
            logger.info("Ignored hold-start while session is not .idle")
        }
    }

    public func cancelCapture() async {
        switch currentSnapshot.sessionState {
        case .capturing, .holdRecording:
            await discardActiveCapture()
        case .idle, .completed, .shortExit, .transcribing, .error:
            logger.info("Ignored cancel from non-active session state")
        }
    }

    public func prepareTranscriber() async throws {
        try await transcriber.prepare()
    }

    /// Install the closure called when VAD fires `.speechEnded`. `SessionCoordinator`
    /// calls this from a post-init Task; until it runs, VAD is cleanly
    /// disabled for any in-flight session — `consumeCaptureStream` snapshots
    /// the handler at session start and skips `makeSession` entirely when
    /// the handler is nil, so no VAD handle is created and no silent-sink
    /// on the one-shot `vadAlreadyFired` flag is possible.
    public func setAutoStopHandler(_ handler: @escaping @Sendable () async -> Void) {
        self.onAutoStopRequested = handler
    }

    /// #078.28 — publish a session-start failure to the snapshot stream
    /// without ever transitioning through `.capturing`. Used by
    /// `SessionCoordinator` when active-recipe re-validation fails: the
    /// pipeline never starts, but observers (pill, ResponseCard) still
    /// see the error rendered through the same `.error(...)` channel
    /// they already drive off.
    public func publishSessionStartError(_ error: PersonalScribeError) {
        let failure = PipelineStageFailure(
            stage: .capture,
            detail: String(describing: error),
            mappedError: error
        )
        handleStageFailure(failure)
    }

    public func snapshot() -> SessionSnapshot {
        currentSnapshot
    }

    public func snapshotStream() -> AsyncStream<SessionSnapshot> {
        let id = UUID()

        return AsyncStream { continuation in
            continuation.yield(self.currentSnapshot)
            self.snapshotContinuations[id] = continuation
            continuation.onTermination = { [self] _ in
                Task {
                    await self.removeSnapshotContinuation(id: id)
                }
            }
        }
    }

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

    public func modelDownloadProgress() -> AsyncStream<ModelDownloadProgress> {
        transcriber.modelDownloadProgress()
    }

    func latestStageFailureForTesting() -> PipelineStageFailure? {
        latestStageFailure
    }

    private func removeSnapshotContinuation(id: UUID) {
        snapshotContinuations[id] = nil
    }

    private func removeAudioLevelContinuation(id: UUID) {
        audioLevelContinuations[id] = nil
    }

    private static func normalizeModelDownloadProgress(
        _ progress: ModelDownloadProgress
    ) -> ModelDownloadProgress? {
        switch progress.phase {
        case .idle, .finished:
            return nil
        case .downloading, .loading:
            return progress
        }
    }

    private func publish(_ mutation: (inout SessionSnapshot) -> Void) {
        let previous = currentSnapshot
        mutation(&currentSnapshot)
        guard currentSnapshot != previous else {
            return
        }
        let snapshot = currentSnapshot
        for continuation in snapshotContinuations.values {
            continuation.yield(snapshot)
        }
    }

    private func publishAudioLevel(_ level: Float) {
        currentAudioLevel = level
        for continuation in audioLevelContinuations.values {
            continuation.yield(level)
        }
    }

    private func startRecording() async {
        bufferedAudio.removeAll(keepingCapacity: true)
        nextRevision = 0
        latestStageFailure = nil
        activeContext = contextProvider.currentContext()
        resetGraceForNewSession()

        do {
            let stream = try await capture.start()
            let levelStream = await capture.audioLevelStream()
            await outputSink.resetForNewSession()

            audioLevelTask?.cancel()
            audioLevelTask = Task { [weak self] in
                for await level in levelStream {
                    await self?.publishAudioLevel(level)
                }
                await self?.publishAudioLevel(0.0)
            }

            // Kick off prepare BEFORE publishing `.capturing` so the
            // detached Task is scheduled before observers see the state
            // transition. Combined with the `.userInitiated` priority in
            // `prepareTranscriberInBackground()`, this closes the first-
            // launch race where prepare wouldn't get scheduler time until
            // the user had already stopped recording — the pill would
            // then sit on `.loading` for minutes. See
            // `plans/backlog/model-download-ux-bug-research.md`
            // (session-start race).
            prepareTranscriberInBackground()

            publish { snapshot in
                snapshot.sessionState = .capturing
                snapshot.activeStage = .capture
                snapshot.transcriptProgress = nil
                snapshot.recordingDuration = .zero
                snapshot.vadAutoStopGracePending = false
                snapshot.vadAutoStopGraceDeadline = nil
                snapshot.vadAutoStopFireToken = nil
            }

            captureTask = Task { [weak self] in
                await self?.consumeCaptureStream(stream)
            }
        } catch {
            handleStageFailure(makeStageFailure(stage: .capture, error: error, fallback: .audioEngineFailure))
        }
    }

    /// True-discard helper shared by `cancelCapture()`. Stops the audio
    /// engine, awaits the capture/level tasks to settle, drops the
    /// in-memory buffer, and publishes `.idle` directly — no
    /// `.transcribing` stage, no output delivery. See `#002`.
    private func discardActiveCapture() async {
        cancelPendingGraceTimer()
        await capture.stop()
        await captureTask?.value
        captureTask = nil

        await audioLevelTask?.value
        audioLevelTask = nil

        bufferedAudio.removeAll(keepingCapacity: true)
        nextRevision = 0
        latestStageFailure = nil

        publish { snapshot in
            snapshot.sessionState = .idle
            snapshot.activeStage = nil
            snapshot.transcriptProgress = nil
            snapshot.recordingDuration = nil
            snapshot.vadAutoStopGracePending = false
            snapshot.vadAutoStopGraceDeadline = nil
            snapshot.vadAutoStopFireToken = nil
        }
    }

    /// Hold-path start. Mirrors `startRecording()` except the target
    /// state (`.holdRecording`) is **published before** awaiting
    /// `capture.start()`. A concurrent hold-release routed through
    /// `toggleCapture()` therefore observes `.holdRecording` and correctly
    /// stops, instead of silently no-opping on `.idle` as it did before
    /// `#071`. Capture failure still flows through `handleStageFailure`,
    /// transitioning state to `.error` — the eager publish is reverted
    /// implicitly by the error publication.
    private func startHoldRecording() async {
        bufferedAudio.removeAll(keepingCapacity: true)
        nextRevision = 0
        latestStageFailure = nil
        activeContext = contextProvider.currentContext()
        resetGraceForNewSession()

        publish { snapshot in
            snapshot.sessionState = .holdRecording
            snapshot.activeStage = .capture
            snapshot.transcriptProgress = nil
            snapshot.recordingDuration = .zero
            snapshot.vadAutoStopGracePending = false
            snapshot.vadAutoStopGraceDeadline = nil
            snapshot.vadAutoStopFireToken = nil
        }

        do {
            let stream = try await capture.start()
            let levelStream = await capture.audioLevelStream()
            await outputSink.resetForNewSession()

            audioLevelTask?.cancel()
            audioLevelTask = Task { [weak self] in
                for await level in levelStream {
                    await self?.publishAudioLevel(level)
                }
                await self?.publishAudioLevel(0.0)
            }

            prepareTranscriberInBackground()

            captureTask = Task { [weak self] in
                await self?.consumeCaptureStream(stream)
            }
        } catch {
            handleStageFailure(makeStageFailure(stage: .capture, error: error, fallback: .audioEngineFailure))
        }
    }

    private func stopRecordingAndRunPipeline() async {
        // Invariant: `capture.stop()` MUST happen BEFORE `captureTask?.value`.
        // The VAD auto-stop path (#046) fires this method from a detached Task
        // while the consumer loop is still live inside `captureTask`. Awaiting
        // `captureTask.value` first would self-wait on the task that hasn't
        // exited yet — the only thing that ends the loop is `capture.stop()`
        // closing the stream. Reversing this order reintroduces the codex-
        // caught deadlock.
        //
        // Cancel any pending VAD grace timer BEFORE tearing down capture, so
        // a timer that's about to fire doesn't publish a spurious fire-token
        // against a session we're already stopping (#046 Stage B).
        cancelPendingGraceTimer()
        await capture.stop()
        await captureTask?.value
        captureTask = nil

        await audioLevelTask?.value
        audioLevelTask = nil

        if case .error = currentSnapshot.sessionState {
            bufferedAudio.removeAll(keepingCapacity: true)
            return
        }

        let replayBuffers = bufferedAudio
        bufferedAudio.removeAll(keepingCapacity: true)
        let bufferedDuration = replayBuffers.reduce(Duration.zero) { $0 + $1.duration }
        currentSnapshot.recordingDuration = bufferedDuration

        guard bufferedDuration >= .milliseconds(1_000) else {
            publish { snapshot in
                // `#075`: Short-hold is a pipeline shortcut (nothing to
                // transcribe), not an error. Publishing `.shortExit`
                // routes through the `.idle` display mapping so entry
                // guards accept the next user action and no wedge
                // occurs.
                snapshot.sessionState = .shortExit
                snapshot.activeStage = nil
                snapshot.recordingDuration = bufferedDuration
                snapshot.vadAutoStopGracePending = false
                snapshot.vadAutoStopGraceDeadline = nil
                snapshot.vadAutoStopFireToken = nil
            }
            return
        }

        // Transition to .transcribing. Clear grace pending/deadline (the
        // timer has been cancelled above). PRESERVE `vadAutoStopFireToken`
        // — if we got here via the VAD-fire path, that token is what the
        // notification driver keys off.
        publish { snapshot in
            snapshot.sessionState = .transcribing
            snapshot.activeStage = .transcription
            snapshot.recordingDuration = bufferedDuration
            snapshot.vadAutoStopGracePending = false
            snapshot.vadAutoStopGraceDeadline = nil
        }

        do {
            let rawResult: TranscriptionResult
            if boundRecipe != nil {
                rawResult = try await runBoundProcessing(replayBuffers: replayBuffers)
            } else {
                rawResult = try await runTranscription(stream: makeReplayStream(from: replayBuffers))
            }
            let rawProgress = nextTranscriptProgress(
                text: rawResult.text,
                isFinal: true,
                sourceStage: .transcription
            )

            publish { snapshot in
                snapshot.sessionState = .transcribing
                snapshot.activeStage = .transcription
                snapshot.transcriptProgress = rawProgress
                snapshot.recordingDuration = rawResult.audioDuration
            }

            try await deliverPartialIfEnabled(rawProgress)

            let postProcessingContext = PostProcessingContext(
                recordingDuration: rawResult.audioDuration,
                activeMode: activeContext.activeMode,
                activeAIModelID: activeContext.activeAIModelID,
                systemPrompt: activeContext.systemPrompt,
                segments: rawResult.segments,
                asrConfidence: nil
            )
            let cleanedText = try await runPostProcessing(rawResult.text, context: postProcessingContext)
            let cleanedProgress = nextTranscriptProgress(
                text: cleanedText,
                isFinal: true,
                sourceStage: .postProcessing
            )

            publish { snapshot in
                snapshot.sessionState = .transcribing
                snapshot.activeStage = .postProcessing
                snapshot.transcriptProgress = cleanedProgress
                snapshot.recordingDuration = rawResult.audioDuration
            }

            try await deliverPartialIfEnabled(cleanedProgress)

            let finalResult = TranscriptionResult(
                text: cleanedText,
                segments: rawResult.segments,
                audioDuration: rawResult.audioDuration,
                processingDuration: rawResult.processingDuration
            )

            publish { snapshot in
                snapshot.sessionState = .transcribing
                snapshot.activeStage = .persistence
                snapshot.transcriptProgress = cleanedProgress
                snapshot.recordingDuration = rawResult.audioDuration
            }

            try await persist(finalResult)

            publish { snapshot in
                snapshot.sessionState = .transcribing
                snapshot.activeStage = .output
                snapshot.transcriptProgress = cleanedProgress
                snapshot.recordingDuration = rawResult.audioDuration
            }

            try await deliverFinal(finalResult)

            publish { snapshot in
                snapshot.sessionState = .completed
                snapshot.activeStage = nil
                snapshot.transcriptProgress = cleanedProgress
                snapshot.lastCompletedResult = finalResult
                snapshot.recordingDuration = rawResult.audioDuration
            }
        } catch let failure as PipelineStageFailure {
            handleStageFailure(failure)
        } catch {
            handleStageFailure(makeStageFailure(stage: .transcription, error: error, fallback: .transcriptionFailure))
        }
    }

    private func runTranscription(
        stream: AsyncThrowingStream<PCMBuffer, Error>
    ) async throws -> TranscriptionResult {
        do {
            return try await transcriber.transcribe(stream: stream)
        } catch {
            throw makeStageFailure(stage: .transcription, error: error, fallback: .transcriptionFailure)
        }
    }

    /// #078.29 — recipe-driven transcription path. Dispatches per
    /// `BoundProcessor` case (per L20 + Phase E sum-type
    /// `ProcessorOutput`). Returns the aggregated `TranscriptionResult`
    /// that the legacy post-processing / persistence / output sink
    /// path consumes unchanged.
    ///
    /// Today's recipes have exactly one processor; the orchestrator
    /// uses the first entry. Multi-processor recipes (e.g. ASR +
    /// voice-ID labelling) land in a follow-up step.
    private func runBoundProcessing(
        replayBuffers: [PCMBuffer]
    ) async throws -> TranscriptionResult {
        guard let recipe = boundRecipe, let processor = recipe.processors.first else {
            throw makeStageFailure(
                stage: .transcription,
                error: PersonalScribeError.invalidState,
                fallback: .transcriptionFailure
            )
        }

        do {
            switch processor {
            case .transcriber(let transcriber):
                let coalesced = try Self.coalesce(replayBuffers)
                return try await transcriber.transcribe(coalesced)

            case .streamingTranscriber(let streamingTranscriber):
                return try await runBoundStreamingTranscription(
                    streamingTranscriber: streamingTranscriber,
                    replayBuffers: replayBuffers
                )

            case .diarizedTurns(let diarizer, let perTurnTranscriber):
                let fusion = DiarizedTurnTranscriptionProcessor(
                    diarizer: diarizer,
                    transcriber: perTurnTranscriber
                )
                let coalesced = try Self.coalesce(replayBuffers)
                let output = try await fusion.process(audio: coalesced, priors: [])
                return try Self.unwrapTextOutput(output)
            }
        } catch let failure as PipelineStageFailure {
            throw failure
        } catch {
            throw makeStageFailure(stage: .transcription, error: error, fallback: .transcriptionFailure)
        }
    }

    /// Stream the replay buffers through a `StreamingTranscriber`,
    /// collect events, and return the terminal `.finalized` result.
    /// Per L26 partial events are not surfaced through the orchestrator
    /// today (that integration lands when streaming-output sinks land);
    /// the orchestrator uses the final aggregated result so the
    /// existing post-process / persist path stays linear.
    private func runBoundStreamingTranscription(
        streamingTranscriber: any StreamingTranscriber,
        replayBuffers: [PCMBuffer]
    ) async throws -> TranscriptionResult {
        let replay = makeReplayStream(from: replayBuffers)
        let events = streamingTranscriber.transcribe(stream: replay)
        var finalResult: TranscriptionResult?
        var lastText: String = ""
        for try await event in events {
            switch event {
            case .partial(let text), .endOfUtterance(let text):
                lastText = text
            case .finalized(let result):
                finalResult = result
            }
        }
        if let finalResult {
            return finalResult
        }
        // Fallback: no `.finalized` arrived — synthesize a TranscriptionResult
        // from the last partial / EOU text plus the buffered audio duration.
        let bufferedDuration = replayBuffers.reduce(Duration.zero) { $0 + $1.duration }
        return TranscriptionResult(
            text: lastText,
            audioDuration: bufferedDuration,
            processingDuration: .zero
        )
    }

    /// Combine a sequence of `PCMBuffer`s with matching format into a
    /// single buffer. Required by the `.transcriber` and
    /// `.diarizedTurns` recipe paths because their adapters consume a
    /// batch buffer (not a stream). Throws when buffers disagree on
    /// `sampleRate` or `channelCount`.
    private static func coalesce(_ buffers: [PCMBuffer]) throws -> PCMBuffer {
        guard let first = buffers.first else {
            return try PCMBuffer(samples: [], timestamp: ContinuousClock().now)
        }
        var combinedSamples: [Float] = []
        combinedSamples.reserveCapacity(buffers.reduce(0) { $0 + $1.samples.count })
        for buffer in buffers {
            guard buffer.sampleRate == first.sampleRate,
                  buffer.channelCount == first.channelCount
            else {
                throw PersonalScribeError.resampleFailure
            }
            combinedSamples.append(contentsOf: buffer.samples)
        }
        return try PCMBuffer(
            samples: combinedSamples,
            sampleRate: first.sampleRate,
            channelCount: first.channelCount,
            timestamp: first.timestamp
        )
    }

    private static func unwrapTextOutput(_ output: ProcessorOutput) throws -> TranscriptionResult {
        if case .text(let result) = output {
            return result
        }
        // Diarized fusion processor always emits `.text`; any other case
        // is a contract violation.
        throw PersonalScribeError.invalidState
    }

    private func runPostProcessing(
        _ text: String,
        context: PostProcessingContext
    ) async throws -> String {
        do {
            return try await postProcessingPipeline.run(text, context: context)
        } catch {
            throw makeStageFailure(stage: .postProcessing, error: error, fallback: .transcriptionFailure)
        }
    }

    private func deliverPartialIfEnabled(_ revision: TranscriptProgress) async throws {
        guard activeContext.streamingOutputEnabled else {
            return
        }

        do {
            try await outputSink.deliverPartial(revision)
        } catch {
            throw makeStageFailure(stage: .output, error: error, fallback: .transcriptionFailure)
        }
    }

    private func persist(_ result: TranscriptionResult) async throws {
        guard let persistenceHandler else {
            return
        }

        let entry = TranscriptEntry(
            id: UUID(),
            timestamp: Date(),
            text: result.text,
            audioDuration: Self.seconds(from: result.audioDuration),
            processingDuration: Self.seconds(from: result.processingDuration)
        )

        do {
            try await persistenceHandler(entry)
        } catch {
            throw makeStageFailure(stage: .persistence, error: error, fallback: .transcriptionFailure)
        }
    }

    private func deliverFinal(_ result: TranscriptionResult) async throws {
        do {
            try await outputSink.deliverFinal(result)
        } catch {
            throw makeStageFailure(stage: .output, error: error, fallback: .transcriptionFailure)
        }
    }

    private func nextTranscriptProgress(
        text: String,
        isFinal: Bool,
        sourceStage: PipelineStepID
    ) -> TranscriptProgress {
        nextRevision += 1
        return TranscriptProgress(
            revision: nextRevision,
            text: text,
            isFinal: isFinal,
            sourceStage: sourceStage
        )
    }

    private func consumeCaptureStream(_ stream: AsyncThrowingStream<PCMBuffer, Error>) async {
        // Snapshot preferences + provider + handler ONCE at session start.
        // Freezing the handler here (not reading `onAutoStopRequested` per-buffer)
        // closes the race where `SessionCoordinator.installAutoStopHandler`
        // hasn't run yet: if the handler is nil at session-start, VAD is never
        // wired in the first place — `makeSession` isn't called and no stale
        // handle can silent-sink the one shot. Mid-session preference flips do
        // not rescue the current recording (documented UX). Hold-mode sessions
        // skip VAD entirely (release is the stop signal).
        //
        // #078.29: when a `BoundRecipe` is set, VAD config comes from the
        // recipe's `BoundCaptureController.vad(...)` entry (per L25 — the
        // recipe builder eager-resolved the parameters). The legacy
        // `vadPreferences` reader is ignored for the duration of the
        // session: the recipe wins. No `.vad` controller in the recipe →
        // no VAD wiring at all.
        let vadPrefs = resolvedVadPreferencesForSession()
        let vadHandler = onAutoStopRequested
        let vadHandle = await makeVadSessionHandleIfApplicable(prefs: vadPrefs, handler: vadHandler)

        do {
            for try await buffer in stream {
                bufferedAudio.append(buffer)
                publish { snapshot in
                    snapshot.recordingDuration = (snapshot.recordingDuration ?? .zero) + buffer.duration
                }
                guard let handle = vadHandle,
                      let handler = vadHandler,
                      let prefs = vadPrefs
                else {
                    continue
                }
                if case .resolved = gracePhase { continue }
                let event = await handle.ingest(buffer.samples)
                switch event {
                case .speechEnded:
                    if case .idle = gracePhase {
                        if prefs.showStoppingWarning {
                            startGracePending(handler: handler)
                        } else {
                            fireAutoStopImmediately(handler: handler)
                        }
                    }
                case .speechResumed:
                    if case .pending(let token, _, _, _) = gracePhase {
                        await resolveGracePending(token: token, trigger: .cancelled)
                    }
                case .none:
                    break
                }
            }
        } catch {
            handleStageFailure(makeStageFailure(stage: .capture, error: error, fallback: .audioEngineFailure))
        }
    }

    /// #078.29 — pick VAD config for this session. Recipe wins when
    /// present: the recipe's `.vad` capture controller's bound
    /// parameters become a `VadPreferences` snapshot for the existing
    /// VAD wiring path. No `.vad` controller → returns nil (skip VAD
    /// entirely; legacy `vadPreferences` reader is also ignored). When
    /// no recipe is bound, fall back to the legacy reader so existing
    /// callers see no behavior change.
    private func resolvedVadPreferencesForSession() -> VadPreferences? {
        if let recipe = boundRecipe {
            for controller in recipe.captureControllers {
                if case .vad(
                    let silenceThreshold,
                    let showWarning,
                    let showAutoStoppedNotification
                ) = controller {
                    return VadPreferences(
                        autoStopEnabled: true,
                        silenceThresholdSeconds: silenceThreshold,
                        showStoppingWarning: showWarning,
                        showAutoStoppedNotification: showAutoStoppedNotification
                    )
                }
            }
            return nil
        }
        return vadPreferences?.current()
    }

    private func makeVadSessionHandleIfApplicable(
        prefs: VadPreferences?,
        handler: (@Sendable () async -> Void)?
    ) async -> VadSessionHandle? {
        guard let provider = vadProvider,
              let prefs,
              prefs.autoStopEnabled,
              handler != nil,
              currentSnapshot.sessionState == .capturing
        else {
            return nil
        }
        return await provider.makeSession(
            silenceThresholdSeconds: prefs.silenceThresholdSeconds
        )
    }

    /// Stage B warn-enabled path: schedule the grace timer, publish
    /// the pending snapshot fields. Timer task calls `resolveGracePending`
    /// when it elapses — the token check there prevents double-fire if a
    /// cleanup path has already moved phase off `.pending`.
    private func startGracePending(handler: @escaping @Sendable () async -> Void) {
        let token = UUID()
        let durationSeconds = graceDurationSeconds
        let deadline = Date().addingTimeInterval(durationSeconds)
        let timerTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(Int(durationSeconds * 1000)))
            if Task.isCancelled { return }
            await self?.resolveGracePending(token: token, trigger: .timerElapsed)
        }
        gracePhase = .pending(token: token, handler: handler, timerTask: timerTask, deadline: deadline)
        publish { snapshot in
            snapshot.vadAutoStopGracePending = true
            snapshot.vadAutoStopGraceDeadline = deadline
        }
    }

    /// Stage A fast path — warn preference off. Fires the handler via a
    /// detached Task (deadlock-avoiding, per Stage A invariant) and
    /// publishes the fire token so the notification path can render if
    /// its own preference is on.
    private func fireAutoStopImmediately(handler: @escaping @Sendable () async -> Void) {
        gracePhase = .resolved
        let fireToken = UUID()
        publish { snapshot in
            snapshot.vadAutoStopFireToken = fireToken
        }
        Task { await handler() }
    }

    /// Single transition gate for `pending → next phase`. Actor-isolated so
    /// timer-elapsed and cleanup paths can race safely — the token check
    /// at the top drops stale invocations.
    ///
    /// Phase transitions:
    /// * `.timerElapsed` → `.resolved` (auto-stop fired; recording is
    ///   ending so VAD ingestion stops via the `if case .resolved` gate
    ///   in `consumeCaptureStream`).
    /// * `.cancelled` → `.idle` (user resumed speaking; the recording
    ///   continues, so VAD must re-arm to detect the next silence
    ///   window. Bug fix: previously set `.resolved` here too, which
    ///   permanently disabled VAD for the rest of the session).
    private func resolveGracePending(token: UUID, trigger: GraceResolveTrigger) async {
        guard case .pending(let currentToken, let handler, let timerTask, _) = gracePhase,
              currentToken == token
        else {
            return
        }
        timerTask.cancel()
        switch trigger {
        case .timerElapsed:
            gracePhase = .resolved
            let fireToken = UUID()
            publish { snapshot in
                snapshot.vadAutoStopGracePending = false
                snapshot.vadAutoStopGraceDeadline = nil
                snapshot.vadAutoStopFireToken = fireToken
            }
            Task { await handler() }
        case .cancelled:
            gracePhase = .idle
            publish { snapshot in
                snapshot.vadAutoStopGracePending = false
                snapshot.vadAutoStopGraceDeadline = nil
            }
        }
    }

    /// Cancel any in-flight timer + transition phase. Used by cleanup
    /// paths (manual stop, cancel, error, new session). Callers publish
    /// their own snapshot mutations — this method does NOT publish, so
    /// grace-clear can be bundled into the caller's state transition
    /// (avoids an intermediate "recording-without-grace" snapshot per
    /// codex review #7).
    private func cancelPendingGraceTimer() {
        if case .pending(_, _, let timerTask, _) = gracePhase {
            timerTask.cancel()
        }
        gracePhase = .resolved
    }

    /// New-session variant — same cancel, but transitions phase to
    /// `.idle` so the next grace window can start fresh.
    private func resetGraceForNewSession() {
        if case .pending(_, _, let timerTask, _) = gracePhase {
            timerTask.cancel()
        }
        gracePhase = .idle
    }

    /// Default grace-window duration. Only overridden in tests (passed via
    /// `graceDurationSeconds:` init arg).
    public static let defaultGraceDurationSeconds: Double = 3.0

    private func handleStageFailure(_ failure: PipelineStageFailure) {
        latestStageFailure = failure
        // Cancel any in-flight VAD grace timer and clear grace + fire-token
        // fields in the SAME publish as `.error`. Without this, observers
        // would see an intermediate `recording + no-grace` snapshot between
        // grace-clear and error-set. Per codex review #7 (#046 Stage B).
        cancelPendingGraceTimer()
        publish { snapshot in
            snapshot.sessionState = .error(failure.mappedError)
            snapshot.activeStage = failure.stage
            snapshot.vadAutoStopGracePending = false
            snapshot.vadAutoStopGraceDeadline = nil
            snapshot.vadAutoStopFireToken = nil
        }
    }

    private func makeReplayStream(from buffers: [PCMBuffer]) -> AsyncThrowingStream<PCMBuffer, Error> {
        AsyncThrowingStream { continuation in
            for buffer in buffers {
                continuation.yield(buffer)
            }
            continuation.finish()
        }
    }

    private func makeStageFailure(
        stage: PipelineStepID,
        error: any Error,
        fallback: PersonalScribeError
    ) -> PipelineStageFailure {
        if let existingFailure = error as? PipelineStageFailure {
            return existingFailure
        }

        return PipelineStageFailure(
            stage: stage,
            detail: detail(for: error),
            mappedError: map(error, default: fallback)
        )
    }

    private func detail(for error: any Error) -> String {
        if let seshatError = error as? PersonalScribeError {
            return String(describing: seshatError)
        }
        return String(describing: error)
    }

    private func map(_ error: any Error, default fallback: PersonalScribeError) -> PersonalScribeError {
        if let stageFailure = error as? PipelineStageFailure {
            return stageFailure.mappedError
        }
        if let seshatError = error as? PersonalScribeError {
            return seshatError
        }

        logger.error("Mapped underlying error to shared contract", error: error)
        return fallback
    }

    private func prepareTranscriberInBackground() {
        let transcriber = transcriber
        let logger = logger

        // `.userInitiated` (was `.background`) so the scheduler runs
        // prepare quickly after it's spawned. At `.background`, prepare
        // could be starved for seconds — the user might stop recording
        // before the first `.downloading` progress tick fires,
        // surfacing the stale `.loading` pill for minutes. See
        // `plans/backlog/model-download-ux-bug-research.md`
        // (session-start race).
        Task.detached(priority: .userInitiated) {
            do {
                try await transcriber.prepare()
            } catch is CancellationError {
                return
            } catch {
                logger.error("Background transcriber preparation failed", error: error)
            }
        }
    }

    private static func seconds(from duration: Duration) -> TimeInterval {
        let components = duration.components
        return TimeInterval(components.seconds)
            + TimeInterval(components.attoseconds) / 1_000_000_000_000_000_000
    }
}
