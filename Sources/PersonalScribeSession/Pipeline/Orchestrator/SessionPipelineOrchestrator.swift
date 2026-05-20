import Foundation
import PersonalScribeCore
import PersonalScribeVAD

public actor SessionPipelineOrchestrator: SessionPipelining {
    private static let liveStreamingFallbackNotice =
        "Live transcript paused. Final result will still appear at stop."
    private let capture: any AudioCapturer
    private let logger: PersonalScribeLogger
    private let postProcessingPipeline: any PostProcessingPipeline
    private let outputSink: any PipelineOutputSink
    private let contextProvider: any PipelineContextProviding
    private let modelLanguagePreference: ModelLanguagePreference?
    private let persistenceHandler: (@Sendable (TranscriptEntry) async throws -> Void)?
    /// VAD provider — nil means the feature is compiled in but not wired (tests)
    /// OR the bundled model failed to load and the provider elected to go silent.
    /// Orchestrator treats either case identically: no VAD monitoring.
    private let vadProvider: (any VadProviding)?
    /// #078.29 — recipe binding for the NEXT session start. Updated by
    /// `SessionCoordinator.bindRecipeForNextSession(_:)` and by eager
    /// prewarm paths (`prepareTranscriber()`). This value is mutable even
    /// while a session is running; `activeSessionRecipe` below snapshots
    /// the recipe actually in use so mid-session rebinds only affect the
    /// next start.
    private var boundRecipe: BoundRecipe?
    /// Session-frozen recipe captured at start and retained through the
    /// completed state so downstream consumers (persistence, menu-bar
    /// output) keep seeing the recipe that actually produced the
    /// transcript. Cleared on true-discard / failed starts; overwritten
    /// on the next successful session start.
    private var activeSessionRecipe: BoundRecipe?
    /// #078.29 — observation Task that forwards the current bound
    /// recipe's processor download progress to
    /// `snapshot.modelDownloadProgress`. Cancelled + replaced when a
    /// new recipe binds.
    private var progressForwardingTask: Task<Void, Never>?
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
    /// Bound the live-stream shutdown wait so a misbehaving adapter
    /// cannot wedge stop/cancel forever by never terminating its event
    /// stream after input closes.
    private let liveStreamingEventShutdownTimeout: Duration

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
    /// Re-entry guard for `startRecording()`. The actor releases during
    /// `await capture.start()`, but `currentSnapshot.sessionState` is still
    /// `.idle` until the post-await `publish(.capturing)` runs (preserving
    /// the deliberate prepare-before-publish invariant at `:415-425`). A
    /// second `toggleCapture()` landing in that window used to re-enter
    /// `startRecording()`, double-call `capture.start()`, and have its
    /// catch null `activeSessionRecipe` out from under the first session.
    /// Set true at the top of `startRecording()`, cleared via `defer` when
    /// the function returns (success or failure).
    private var startRecordingInFlight = false
    private var snapshotContinuations: [UUID: AsyncStream<SessionSnapshot>.Continuation] = [:]
    private var bufferedAudio: [PCMBuffer] = []
    private var captureTask: Task<Void, Never>?
    private var liveStreamingInputContinuation:
        AsyncThrowingStream<PCMBuffer, Error>.Continuation?
    private var liveStreamingEventTask: Task<Void, Never>?
    private var liveStreamingAccumulator: StreamingTranscriptAccumulator?
    private var liveStreamingFailure: PipelineStageFailure?
    private var audioLevelContinuations: [UUID: AsyncStream<Float>.Continuation] = [:]
    private var currentAudioLevel: Float = 0.0
    private var audioLevelTask: Task<Void, Never>?
    private var nextRevision = 0

    public init(
        capture: any AudioCapturer,
        transcriptRepository: TranscriptRepository? = nil,
        logger: PersonalScribeLogger,
        postProcessingPipeline: any PostProcessingPipeline = DefaultPostProcessingPipeline(),
        outputSink: any PipelineOutputSink,
        contextProvider: any PipelineContextProviding,
        modelLanguagePreference: ModelLanguagePreference? = nil,
        vadProvider: (any VadProviding)? = nil,
        boundRecipe: BoundRecipe? = nil,
        graceDurationSeconds: Double = SessionPipelineOrchestrator.defaultGraceDurationSeconds,
        liveStreamingEventShutdownTimeout: Duration = .seconds(2)
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
            logger: logger,
            postProcessingPipeline: postProcessingPipeline,
            outputSink: outputSink,
            contextProvider: contextProvider,
            modelLanguagePreference: modelLanguagePreference,
            persistenceHandler: persistenceHandler,
            vadProvider: vadProvider,
            boundRecipe: boundRecipe,
            graceDurationSeconds: graceDurationSeconds,
            liveStreamingEventShutdownTimeout: liveStreamingEventShutdownTimeout
        )
    }

    init(
        capture: any AudioCapturer,
        logger: PersonalScribeLogger,
        postProcessingPipeline: any PostProcessingPipeline,
        outputSink: any PipelineOutputSink,
        contextProvider: any PipelineContextProviding,
        modelLanguagePreference: ModelLanguagePreference? = nil,
        persistenceHandler: (@Sendable (TranscriptEntry) async throws -> Void)?,
        vadProvider: (any VadProviding)? = nil,
        boundRecipe: BoundRecipe? = nil,
        graceDurationSeconds: Double = SessionPipelineOrchestrator.defaultGraceDurationSeconds,
        liveStreamingEventShutdownTimeout: Duration = .seconds(2)
    ) {
        let initialContext = contextProvider.currentContext()
        self.capture = capture
        self.logger = logger
        self.postProcessingPipeline = postProcessingPipeline
        self.outputSink = outputSink
        self.contextProvider = contextProvider
        self.modelLanguagePreference = modelLanguagePreference
        self.persistenceHandler = persistenceHandler
        self.vadProvider = vadProvider
        self.boundRecipe = boundRecipe
        self.graceDurationSeconds = graceDurationSeconds
        self.liveStreamingEventShutdownTimeout = liveStreamingEventShutdownTimeout
        self.activeContext = initialContext
        self.currentSnapshot = SessionSnapshot()
    }

    /// #078.29 — bind a fresh recipe ahead of the next session.
    /// `SessionCoordinator` calls this immediately before
    /// `toggleCapture` / `startHoldCapture`. Cancels any prior
    /// progress-forwarding Task and starts observing the new recipe's
    /// processor download progress (which lands in
    /// `snapshot.modelDownloadProgress` for UI consumers).
    public func bindRecipeForNextSession(_ recipe: BoundRecipe) {
        boundRecipe = recipe
        progressForwardingTask?.cancel()
        progressForwardingTask = makeProgressForwardingTask(for: recipe)
    }

    /// #089 — read the session-frozen recipe currently in effect. Falls
    /// back to the next-session binding before the first successful
    /// session has started. `MenuBarSceneModel.deliverBatch(text:)`
    /// consumes this to drive output via the session-frozen sink list
    /// (per L-24 — never falls back to the live registry mid-delivery).
    public func currentBoundRecipe() -> BoundRecipe? {
        activeSessionRecipe ?? boundRecipe
    }

    private func makeProgressForwardingTask(for recipe: BoundRecipe) -> Task<Void, Never>? {
        guard let lifecycle = Self.lifecycleForObservation(in: recipe) else {
            return nil
        }
        // Extract the stream BEFORE entering the Task body so the Task
        // doesn't capture `lifecycle` (the adapter) strongly. The Task
        // captures only the AsyncStream value; once the recipe is
        // replaced and `provider.records` is evicted, the adapter has
        // no remaining references and can dealloc — its broadcaster's
        // deinit then `finish()`-es the continuation, the for-await
        // exits, and this Task body completes.
        //
        // Without this extraction, the task body's
        // `lifecycle.modelDownloadProgress()` capture pinned the
        // adapter alive for the process lifetime — a 1+ GB MLModel
        // weight leak per Activate switch.
        let stream = lifecycle.modelDownloadProgress()
        return Task { [weak self] in
            for await progress in stream {
                if Task.isCancelled { return }
                await self?.publish { snapshot in
                    snapshot.modelDownloadProgress = Self.normalizeModelDownloadProgress(progress)
                }
            }
        }
    }

    /// Pick the lifecycle whose progress feeds the snapshot. Today's
    /// recipes have one processor; the asr-side processor (the
    /// transcriber) is the canonical UI signal. Multi-processor recipes
    /// (diarized fusion) report via the per-turn transcriber.
    private static func lifecycleForObservation(in recipe: BoundRecipe) -> (any ModelLifecycle)? {
        guard let processor = recipe.processors.first else {
            return nil
        }
        switch processor {
        case .transcriber(let transcriber):
            return transcriber
        case .streamingTranscriber(let streamingTranscriber):
            return streamingTranscriber
        case .diarizedTurns(_, let transcriber, _):
            return transcriber
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
                snapshot.liveStreamingFallbackNotice = nil
                snapshot.isStreamingSession = false
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
                snapshot.liveStreamingFallbackNotice = nil
                snapshot.isStreamingSession = false
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
        guard let recipe = boundRecipe else {
            return
        }
        try await Self.prepareAllProcessors(in: recipe)
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
    public func publishSessionStartError(
        _ error: PersonalScribeError,
        file: StaticString = #fileID,
        function: StaticString = #function,
        line: UInt = #line
    ) {
        let detail = String(describing: error)
        let reportedError = reportStageError(
            error,
            mappedError: error,
            stage: .capture,
            detail: detail,
            file: file,
            function: function,
            line: line
        )
        let failure = PipelineStageFailure(
            stage: .capture,
            detail: detail,
            mappedError: error,
            reportedError: reportedError
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
        if case .error = currentSnapshot.sessionState {
            // Keep the failure payload attached to error snapshots until
            // the next non-error transition.
        } else {
            currentSnapshot.reportedError = nil
        }
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

    private func logSessionStartedBound(sessionRecipe: BoundRecipe?, holdToRecord: Bool) {
        guard let recipe = sessionRecipe else {
            logger.info("session_started_bound — recipe=nil holdToRecord=\(holdToRecord)")
            return
        }
        let processorTypes = recipe.processors.map { processor -> String in
            switch processor {
            case .transcriber:
                return "transcriber"
            case .streamingTranscriber:
                return "streamingTranscriber"
            case .diarizedTurns:
                return "diarizedTurns"
            }
        }.joined(separator: ",")
        let streamingBehaviorDesc: String
        if let behavior = recipe.streamingBehavior {
            streamingBehaviorDesc = "liveCard=\(behavior.liveCardEnabled),liveCursor=\(behavior.liveCursorEnabled),secondPass=\(behavior.secondPassEnabled)"
        } else {
            streamingBehaviorDesc = "nil"
        }
        let secondPassDesc = recipe.streamingSecondPassTranscriber == nil ? "nil" : "set"
        logger.info(
            "session_started_bound — recipeID=\(recipe.recipeID) recipeName=\(recipe.recipeName) pipelineShape=\(recipe.pipelineShape.rawValue) processors=[\(processorTypes)] streamingBehavior=\(streamingBehaviorDesc) secondPassTranscriber=\(secondPassDesc) holdToRecord=\(holdToRecord)"
        )
    }

    private func startRecording() async {
        guard !startRecordingInFlight else {
            logger.info("Ignored re-entrant startRecording while a prior start is still awaiting capture.start()")
            return
        }
        startRecordingInFlight = true
        defer { startRecordingInFlight = false }

        bufferedAudio.removeAll(keepingCapacity: true)
        nextRevision = 0
        latestStageFailure = nil
        activeContext = contextProvider.currentContext()
        resetGraceForNewSession()
        let sessionRecipe = boundRecipe
        activeSessionRecipe = sessionRecipe
        logSessionStartedBound(sessionRecipe: sessionRecipe, holdToRecord: false)

        do {
            let stream = try await capture.start()
            let levelStream = await capture.audioLevelStream()
            await outputSink.resetForNewSession()
            beginLiveStreamingSessionIfNeeded(for: sessionRecipe)

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
            prepareTranscriberInBackground(for: sessionRecipe)

            publish { snapshot in
                snapshot.sessionState = .capturing
                snapshot.activeStage = .capture
                snapshot.transcriptProgress = nil
                snapshot.recordingDuration = .zero
                snapshot.liveStreamingFallbackNotice = nil
                snapshot.isStreamingSession = sessionRecipe?.streamingBehavior != nil
                snapshot.vadAutoStopGracePending = false
                snapshot.vadAutoStopGraceDeadline = nil
                snapshot.vadAutoStopFireToken = nil
            }

            captureTask = Task { [weak self] in
                await self?.consumeCaptureStream(stream)
            }
        } catch {
            // Do NOT null `activeSessionRecipe` here. The intentional
            // clear lives on the cancel/discard path
            // (`discardActiveCapture`); nulling here would corrupt a
            // concurrent winning session whose recipe we share. The
            // next `startRecording()` / `startHoldRecording()`
            // overwrites `activeSessionRecipe` unconditionally, so a
            // stale value after a solo failed start is harmless.
            // (Codex review 2026-05-02.)
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
        await cancelLiveStreamingSession()

        bufferedAudio.removeAll(keepingCapacity: true)
        nextRevision = 0
        latestStageFailure = nil
        activeSessionRecipe = nil

        await outputSink.endSession()

        publish { snapshot in
            snapshot.sessionState = .idle
            snapshot.activeStage = nil
            snapshot.transcriptProgress = nil
            snapshot.recordingDuration = nil
            snapshot.liveStreamingFallbackNotice = nil
            snapshot.isStreamingSession = false
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
        let sessionRecipe = boundRecipe
        activeSessionRecipe = sessionRecipe
        logSessionStartedBound(sessionRecipe: sessionRecipe, holdToRecord: true)

        publish { snapshot in
            snapshot.sessionState = .holdRecording
            snapshot.activeStage = .capture
            snapshot.transcriptProgress = nil
            snapshot.recordingDuration = .zero
            snapshot.liveStreamingFallbackNotice = nil
            snapshot.isStreamingSession = sessionRecipe?.streamingBehavior != nil
            snapshot.vadAutoStopGracePending = false
            snapshot.vadAutoStopGraceDeadline = nil
            snapshot.vadAutoStopFireToken = nil
        }

        do {
            let stream = try await capture.start()
            let levelStream = await capture.audioLevelStream()
            await outputSink.resetForNewSession()
            beginLiveStreamingSessionIfNeeded(for: sessionRecipe)

            audioLevelTask?.cancel()
            audioLevelTask = Task { [weak self] in
                for await level in levelStream {
                    await self?.publishAudioLevel(level)
                }
                await self?.publishAudioLevel(0.0)
            }

            prepareTranscriberInBackground(for: sessionRecipe)

            captureTask = Task { [weak self] in
                await self?.consumeCaptureStream(stream)
            }
        } catch {
            // Do NOT null `activeSessionRecipe` here. The intentional
            // clear lives on the cancel/discard path
            // (`discardActiveCapture`); nulling here would corrupt a
            // concurrent winning session whose recipe we share. The
            // next `startRecording()` / `startHoldRecording()`
            // overwrites `activeSessionRecipe` unconditionally, so a
            // stale value after a solo failed start is harmless.
            // (Codex review 2026-05-02.)
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
            await cancelLiveStreamingSession()
            bufferedAudio.removeAll(keepingCapacity: true)
            return
        }

        let replayBuffers = bufferedAudio
        bufferedAudio.removeAll(keepingCapacity: true)
        let bufferedDuration = replayBuffers.reduce(Duration.zero) { $0 + $1.duration }
        currentSnapshot.recordingDuration = bufferedDuration
        let isStreamingSession = activeSessionRecipe?.streamingBehavior != nil
        var finishedLiveStreamingState:
            (accumulator: StreamingTranscriptAccumulator?, failure: PipelineStageFailure?)?
        let canFinalizeShortStreamingCapture: Bool
        if isStreamingSession, bufferedDuration < .milliseconds(1_000) {
            let liveState = await finishLiveStreamingSessionForStop()
            finishedLiveStreamingState = liveState
            canFinalizeShortStreamingCapture = resolveStreamingFallbackResult(
                accumulator: liveState.accumulator,
                bufferedDuration: bufferedDuration
            ) != nil
        } else {
            canFinalizeShortStreamingCapture = false
        }

        guard bufferedDuration >= .milliseconds(1_000) || canFinalizeShortStreamingCapture else {
            if isStreamingSession, finishedLiveStreamingState == nil {
                await cancelLiveStreamingSession()
            }
            await outputSink.endSession()
            publish { snapshot in
                // `#075`: Short-hold is a pipeline shortcut (nothing to
                // transcribe), not an error. Publishing `.shortExit`
                // routes through the `.idle` display mapping so entry
                // guards accept the next user action and no wedge
                // occurs.
                //
                // Streaming sessions only bypass the sub-1s short-exit
                // guard when the stop-finalized live path has
                // accumulated non-blank transcript text. Blank/no-event
                // short clips still exit here.
                snapshot.sessionState = .shortExit
                snapshot.activeStage = nil
                snapshot.recordingDuration = bufferedDuration
                snapshot.liveStreamingFallbackNotice = nil
                snapshot.isStreamingSession = false
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
            snapshot.liveStreamingFallbackNotice = nil
            snapshot.vadAutoStopGracePending = false
            snapshot.vadAutoStopGraceDeadline = nil
        }

        do {
            let rawResult = try await runBoundProcessing(
                replayBuffers: replayBuffers,
                finishedLiveStreamingState: finishedLiveStreamingState
            )
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
            await outputSink.endSession()

            publish { snapshot in
                snapshot.sessionState = .completed
                snapshot.activeStage = nil
                snapshot.transcriptProgress = cleanedProgress
                snapshot.lastCompletedResult = finalResult
                snapshot.recordingDuration = rawResult.audioDuration
                snapshot.liveStreamingFallbackNotice = nil
                snapshot.isStreamingSession = false
            }
        } catch let failure as PipelineStageFailure {
            await outputSink.endSession()
            handleStageFailure(failure)
        } catch {
            await outputSink.endSession()
            handleStageFailure(makeStageFailure(stage: .transcription, error: error, fallback: .transcriptionFailure))
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
        replayBuffers: [PCMBuffer],
        finishedLiveStreamingState:
            (accumulator: StreamingTranscriptAccumulator?, failure: PipelineStageFailure?)? = nil
    ) async throws -> TranscriptionResult {
        guard let recipe = activeSessionRecipe, let processor = recipe.processors.first else {
            throw makeStageFailure(
                stage: .transcription,
                error: PersonalScribeError.invalidState,
                fallback: .transcriptionFailure
            )
        }

        do {
            let languageHint = await resolveLanguageHintForCurrentMode()
            switch processor {
            case .transcriber(let transcriber):
                let coalesced = try Self.coalesce(replayBuffers)
                return try await transcriber.transcribe(
                    coalesced,
                    languageHint: languageHint
                )

            case .streamingTranscriber:
                return try await runBoundStreamingTranscription(
                    replayBuffers: replayBuffers,
                    finishedLiveStreamingState: finishedLiveStreamingState
                )

            case .diarizedTurns(let diarizer, let perTurnTranscriber, let sensitivity):
                let fusion = DiarizedTurnTranscriptionProcessor(
                    diarizer: diarizer,
                    transcriber: perTurnTranscriber,
                    sensitivity: sensitivity,
                    languageHint: languageHint
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

    /// Finalize a capture-time live streaming session and optionally
    /// run an authoritative second pass over the buffered audio.
    private func runBoundStreamingTranscription(
        replayBuffers: [PCMBuffer],
        finishedLiveStreamingState:
            (accumulator: StreamingTranscriptAccumulator?, failure: PipelineStageFailure?)? = nil
    ) async throws -> TranscriptionResult {
        let bufferedDuration = replayBuffers.reduce(Duration.zero) { $0 + $1.duration }
        let (accumulator, liveFailure) = if let finishedLiveStreamingState {
            finishedLiveStreamingState
        } else {
            await finishLiveStreamingSessionForStop()
        }

        let streamingFallbackResult = resolveStreamingFallbackResult(
            accumulator: accumulator,
            bufferedDuration: bufferedDuration
        )

        if let secondPassTranscriber = activeSessionRecipe?.streamingSecondPassTranscriber {
            do {
                if let authoritativeResult = try await runStreamingSecondPass(
                    with: secondPassTranscriber,
                    replayBuffers: replayBuffers
                ) {
                    return authoritativeResult
                }
            } catch {
                logger.error("Streaming second pass failed; falling back to streaming final", error: error)
                if streamingFallbackResult == nil {
                    throw makeStageFailure(
                        stage: .transcription,
                        error: error,
                        fallback: .transcriptionFailure
                    )
                }
            }
        }

        if let streamingFallbackResult {
            return streamingFallbackResult
        }

        if let liveFailure {
            throw liveFailure
        }

        throw makeStageFailure(
            stage: .transcription,
            error: PersonalScribeError.transcriptionFailure,
            fallback: .transcriptionFailure
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
            processingDuration: Self.seconds(from: result.processingDuration),
            // #027 — bound recipe is the source of truth for "which mode
            // produced this transcript" at session-start binding time.
            // Read the session-frozen snapshot, not the mutable
            // next-session binding, so eager prewarm / mode switches that
            // happen while we are transcribing cannot rewrite history.
            // `nil` only when no recipe was frozen for the session
            // (legacy / fixed-recipe test paths); production
            // session-starts always bind.
            modeId: activeSessionRecipe?.recipeID
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
        // #078.29: VAD config comes from the bound recipe's
        // `BoundCaptureController.vad(...)` entry (per L25 — the
        // recipe builder eager-resolved the parameters). No `.vad`
        // controller in the recipe → no VAD wiring at all.
        let vadPrefs = resolvedVadPreferencesForSession()
        let vadHandler = onAutoStopRequested
        let vadHandle = await makeVadSessionHandleIfApplicable(prefs: vadPrefs, handler: vadHandler)

        do {
            for try await buffer in stream {
                bufferedAudio.append(buffer)
                if liveStreamingFailure == nil {
                    liveStreamingInputContinuation?.yield(buffer)
                }
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
            await cancelLiveStreamingSession()
            await outputSink.endSession()
            handleStageFailure(makeStageFailure(stage: .capture, error: error, fallback: .audioEngineFailure))
        }
    }

    /// #078.29 + #089 — pick VAD config for this session from the
    /// bound recipe's `.vad` capture controller. No `.vad` controller
    /// (or no bound recipe) → returns nil. **`enabled: false`** on a
    /// present `.vad` also returns nil — orchestrator skips VAD
    /// monitoring entirely (#089 L-4 / CHECKLIST critical-1).
    private func resolvedVadPreferencesForSession() -> VadPreferences? {
        guard let recipe = activeSessionRecipe else {
            return nil
        }
        for controller in recipe.captureControllers {
            if case .vad(
                let enabled,
                let silenceThreshold,
                let showWarning,
                let showAutoStoppedNotification
            ) = controller {
                guard enabled else { return nil }
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
        let reportedError = failure.reportedError ?? reportStageError(
            failure,
            mappedError: failure.mappedError,
            stage: failure.stage,
            detail: failure.detail
        )
        publish { snapshot in
            snapshot.sessionState = .error(failure.mappedError)
            snapshot.activeStage = failure.stage
            snapshot.reportedError = reportedError
            snapshot.liveStreamingFallbackNotice = nil
            snapshot.isStreamingSession = false
            snapshot.vadAutoStopGracePending = false
            snapshot.vadAutoStopGraceDeadline = nil
            snapshot.vadAutoStopFireToken = nil
        }
    }

    private func makeStageFailure(
        stage: PipelineStepID,
        error: any Error,
        fallback: PersonalScribeError,
        file: StaticString = #fileID,
        function: StaticString = #function,
        line: UInt = #line
    ) -> PipelineStageFailure {
        if let existingFailure = error as? PipelineStageFailure {
            return existingFailure
        }

        let detail = detail(for: error)
        let mappedError = map(error, default: fallback)
        let reportedError = reportStageError(
            error,
            mappedError: mappedError,
            stage: stage,
            detail: detail,
            file: file,
            function: function,
            line: line
        )
        return PipelineStageFailure(
            stage: stage,
            detail: detail,
            mappedError: mappedError,
            reportedError: reportedError
        )
    }

    private func detail(for error: any Error) -> String {
        if let seshatError = error as? PersonalScribeError {
            return String(describing: seshatError)
        }
        return String(describing: error)
    }

    private func reportStageError(
        _ error: any Error,
        mappedError: PersonalScribeError,
        stage: PipelineStepID,
        detail: String,
        file: StaticString = #fileID,
        function: StaticString = #function,
        line: UInt = #line
    ) -> ReportedError {
        let event = logger.error(
            "Session pipeline failed",
            error: error,
            metadata: [
                "mappedError": String(describing: mappedError),
                "stage": stage.rawValue,
                "detail": detail,
            ],
            userFacing: .sessionError(mapped: mappedError),
            file: file,
            function: function,
            line: line
        )

        return ReportedError(event: event) ?? ReportedError(
            mappedError: mappedError,
            userMessage: ReportedError.userMessage(for: mappedError),
            detail: detail,
            timestamp: event.timestamp,
            category: event.category,
            context: event.metadata
        )
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

    private func prepareTranscriberInBackground(for recipe: BoundRecipe?) {
        guard let recipe else {
            return
        }
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
                try await Self.prepareAllProcessors(in: recipe)
            } catch is CancellationError {
                return
            } catch {
                logger.error("Background recipe preparation failed", error: error)
            }
        }
    }

    private func beginLiveStreamingSessionIfNeeded(for recipe: BoundRecipe?) {
        liveStreamingEventTask?.cancel()
        liveStreamingInputContinuation = nil
        liveStreamingEventTask = nil
        liveStreamingAccumulator = nil
        liveStreamingFailure = nil

        guard let recipe else {
            logger.info("streaming_session_skipped — reason=no_recipe")
            return
        }
        guard let processor = recipe.processors.first else {
            logger.info("streaming_session_skipped — reason=no_processor recipeID=\(recipe.recipeID)")
            return
        }
        guard case .streamingTranscriber(let streamingTranscriber) = processor else {
            let processorType: String
            switch processor {
            case .transcriber:
                processorType = "transcriber"
            case .streamingTranscriber:
                processorType = "streamingTranscriber"
            case .diarizedTurns:
                processorType = "diarizedTurns"
            }
            logger.info(
                "streaming_session_skipped — reason=non_streaming_processor recipeID=\(recipe.recipeID) processorType=\(processorType)"
            )
            return
        }
        logger.info(
            "streaming_session_started — recipeID=\(recipe.recipeID) processorTypeName=\(String(describing: type(of: streamingTranscriber)))"
        )

        let (inputStream, continuation) = Self.makeLiveStreamingInputStream()
        let events = streamingTranscriber.transcribe(stream: inputStream)
        let liveCardEnabled = recipe.streamingBehavior?.liveCardEnabled ?? false
        let liveCursorEnabled = recipe.streamingBehavior?.liveCursorEnabled ?? false

        liveStreamingInputContinuation = continuation
        liveStreamingAccumulator = StreamingTranscriptAccumulator()
        liveStreamingEventTask = Task { [weak self] in
            do {
                for try await event in events {
                    await self?.consumeLiveStreamingEvent(
                        event,
                        liveCardEnabled: liveCardEnabled,
                        liveCursorEnabled: liveCursorEnabled
                    )
                }
            } catch {
                await self?.recordLiveStreamingFailure(error, liveCardEnabled: liveCardEnabled)
            }
        }
    }

    private func consumeLiveStreamingEvent(
        _ event: StreamingTranscriptionEvent,
        liveCardEnabled: Bool,
        liveCursorEnabled: Bool
    ) async {
        guard var accumulator = liveStreamingAccumulator else {
            return
        }

        let text = accumulator.apply(event)
        liveStreamingAccumulator = accumulator

        if liveCardEnabled {
            switch event {
            case .partial, .endOfUtterance:
                let nextText = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                publish { snapshot in
                    snapshot.transcriptProgress = nextText.isEmpty
                        ? nil
                        : nextTranscriptProgress(
                            text: nextText,
                            isFinal: false,
                            sourceStage: .transcription
                        )
                }
            case .finalized:
                break
            }
        }

        // #033 — append-only EOU cursor delivery. Each end-of-utterance
        // chunk is the new text to append to the user's frontmost text
        // field via the live cursor output sink. `.partial` events do
        // not deliver (per #056 DESIGN locked: "EOU chunks only").
        // Failure is logged-and-continued — a transient cursor delivery
        // glitch should not tear down the session.
        if liveCursorEnabled, case .endOfUtterance(let chunkText) = event {
            let trimmed = chunkText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                let progress = nextTranscriptProgress(
                    text: trimmed,
                    isFinal: false,
                    sourceStage: .transcription
                )
                do {
                    try await outputSink.deliverPartial(progress)
                } catch {
                    logger.error("Live cursor chunk delivery failed; continuing session", error: error)
                }
            }
        }
    }

    private func recordLiveStreamingFailure(
        _ error: any Error,
        liveCardEnabled: Bool
    ) {
        guard liveStreamingEventTask != nil || liveStreamingAccumulator != nil else {
            return
        }
        logger.error("Live streaming transcription failed; falling back at stop", error: error)
        liveStreamingFailure = makeStageFailure(
            stage: .transcription,
            error: error,
            fallback: .transcriptionFailure
        )
        publish { snapshot in
            snapshot.liveStreamingFallbackNotice = Self.liveStreamingFallbackNotice
            if liveCardEnabled {
                snapshot.transcriptProgress = nil
            }
        }
    }

    private func finishLiveStreamingSessionForStop()
        async -> (accumulator: StreamingTranscriptAccumulator?, failure: PipelineStageFailure?)
    {
        liveStreamingInputContinuation?.finish()
        liveStreamingInputContinuation = nil

        if let liveStreamingEventTask {
            await awaitLiveStreamingEventTaskShutdown(
                liveStreamingEventTask,
                cancelImmediately: false
            )
        }

        let accumulator = liveStreamingAccumulator
        let failure = liveStreamingFailure

        liveStreamingEventTask = nil
        liveStreamingAccumulator = nil
        liveStreamingFailure = nil
        return (accumulator, failure)
    }

    private func cancelLiveStreamingSession() async {
        liveStreamingInputContinuation?.finish()
        liveStreamingInputContinuation = nil

        if let liveStreamingEventTask {
            await awaitLiveStreamingEventTaskShutdown(
                liveStreamingEventTask,
                cancelImmediately: true
            )
        }

        liveStreamingEventTask = nil
        liveStreamingAccumulator = nil
        liveStreamingFailure = nil
    }

    private func awaitLiveStreamingEventTaskShutdown(
        _ task: Task<Void, Never>,
        cancelImmediately: Bool
    ) async {
        if cancelImmediately {
            task.cancel()
        }

        if await Self.waitForTaskCompletion(
            task,
            timeout: liveStreamingEventShutdownTimeout
        ) {
            return
        }

        if !cancelImmediately {
            logger.error(
                "Live streaming event task exceeded graceful shutdown timeout; cancelling",
                metadata: ["timeout": "\(liveStreamingEventShutdownTimeout)"]
            )
            task.cancel()
            if await Self.waitForTaskCompletion(
                task,
                timeout: liveStreamingEventShutdownTimeout
            ) {
                return
            }
        }

        logger.error(
            "Live streaming event task exceeded shutdown timeout",
            metadata: [
                "timeout": "\(liveStreamingEventShutdownTimeout)",
                "cancelImmediately": "\(cancelImmediately)"
            ]
        )
    }

    private actor TaskCompletionTracker {
        private(set) var isCompleted = false

        func markCompleted() {
            isCompleted = true
        }
    }

    private static func waitForTaskCompletion(
        _ task: Task<Void, Never>,
        timeout: Duration
    ) async -> Bool {
        let tracker = TaskCompletionTracker()
        let waiter = Task {
            await task.value
            await tracker.markCompleted()
        }

        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            if await tracker.isCompleted {
                waiter.cancel()
                return true
            }
            try? await Task.sleep(for: .milliseconds(5))
        }

        waiter.cancel()
        return await tracker.isCompleted
    }

    private func resolveStreamingFallbackResult(
        accumulator: StreamingTranscriptAccumulator?,
        bufferedDuration: Duration
    ) -> TranscriptionResult? {
        if let terminalFinalResult = accumulator?.terminalFinalResult {
            let text = terminalFinalResult.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                return terminalFinalResult
            }
        }

        let terminalText = accumulator?.terminalText.trimmingCharacters(
            in: .whitespacesAndNewlines
        ) ?? ""
        guard !terminalText.isEmpty else {
            return nil
        }

        return TranscriptionResult(
            text: terminalText,
            audioDuration: bufferedDuration,
            processingDuration: .zero
        )
    }

    private func runStreamingSecondPass(
        with transcriber: any Transcriber,
        replayBuffers: [PCMBuffer]
    ) async throws -> TranscriptionResult? {
        try await transcriber.prepare()
        let coalesced = try Self.coalesce(replayBuffers)
        let languageHint = await resolveLanguageHintForCurrentMode()
        let result = try await transcriber.transcribe(
            coalesced,
            languageHint: languageHint
        )
        let trimmed = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }
        return result
    }

    private func resolveLanguageHintForCurrentMode() async -> String? {
        guard
            let modelLanguagePreference,
            let descriptorID = pinnedASRDescriptorIDForLanguageHint(in: activeContext.activeMode)
        else {
            return nil
        }

        return await modelLanguagePreference.hint(for: descriptorID)
    }

    private func pinnedASRDescriptorIDForLanguageHint(
        in mode: WorkflowMode?
    ) -> String? {
        guard let mode else {
            return nil
        }

        for processor in mode.processors {
            switch processor {
            case .transcriber(let kind, let descriptorID) where kind == .asr:
                if let descriptorID {
                    return descriptorID
                }
            case .diarizedTurns(_, let transcriberKind, let descriptorID, _)
                where transcriberKind == .asr:
                if let descriptorID {
                    return descriptorID
                }
            default:
                continue
            }
        }

        return nil
    }

    /// Sequentially prepare every processor referenced by `recipe`.
    /// Each adapter's `prepare()` coalesces repeat calls; sequential
    /// ordering keeps coremldata.bin contention low on first-launch
    /// downloads.
    private static func prepareAllProcessors(in recipe: BoundRecipe) async throws {
        for processor in recipe.processors {
            switch processor {
            case .transcriber(let transcriber):
                try await transcriber.prepare()
            case .streamingTranscriber(let streamingTranscriber):
                try await streamingTranscriber.prepare()
            case .diarizedTurns(let diarizer, let transcriber, let sensitivity):
                // Apply the per-session sensitivity preset before
                // prepare() so the FluidAudio adapter rebuilds its
                // OfflineDiarizerManager with the resolved config.
                await diarizer.applySensitivity(sensitivity)
                try await diarizer.prepare()
                try await transcriber.prepare()
            }
        }
        if let secondPassTranscriber = recipe.streamingSecondPassTranscriber {
            try await secondPassTranscriber.prepare()
        }
    }

    private static func seconds(from duration: Duration) -> TimeInterval {
        let components = duration.components
        return TimeInterval(components.seconds)
            + TimeInterval(components.attoseconds) / 1_000_000_000_000_000_000
    }

    private static func makeLiveStreamingInputStream()
        -> (
            AsyncThrowingStream<PCMBuffer, Error>,
            AsyncThrowingStream<PCMBuffer, Error>.Continuation
        )
    {
        var capturedContinuation: AsyncThrowingStream<PCMBuffer, Error>.Continuation?
        let stream = AsyncThrowingStream<PCMBuffer, Error> { continuation in
            capturedContinuation = continuation
        }
        return (stream, capturedContinuation!)
    }
}
