import Foundation
import PersonalScribeCore

public actor SessionPipelineOrchestrator: SessionPipelining {
    private let capture: any AudioCapturing
    private let transcriber: any Transcribing
    private let logger: PersonalScribeLogger
    private let postProcessingPipeline: any PostProcessingPipeline
    private let outputSink: any PipelineOutputSink
    private let contextProvider: any PipelineContextProviding
    private let persistenceHandler: (@Sendable (TranscriptEntry) async throws -> Void)?

    private var currentSnapshot: PipelineSnapshot
    private var activeContext: PipelineContextSnapshot
    private var latestStageFailure: PipelineStageFailure?
    private var snapshotContinuations: [UUID: AsyncStream<PipelineSnapshot>.Continuation] = [:]
    private var bufferedAudio: [PCMBuffer] = []
    private var captureTask: Task<Void, Never>?
    private var audioLevelContinuations: [UUID: AsyncStream<Float>.Continuation] = [:]
    private var currentAudioLevel: Float = 0.0
    private var audioLevelTask: Task<Void, Never>?
    private var nextRevision = 0

    public init(
        capture: any AudioCapturing,
        transcriber: any Transcribing,
        transcriptRepository: TranscriptRepository? = nil,
        logger: PersonalScribeLogger,
        postProcessingPipeline: any PostProcessingPipeline = DefaultPostProcessingPipeline(),
        outputSink: any PipelineOutputSink,
        contextProvider: any PipelineContextProviding
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
            persistenceHandler: persistenceHandler
        )
    }

    init(
        capture: any AudioCapturing,
        transcriber: any Transcribing,
        logger: PersonalScribeLogger,
        postProcessingPipeline: any PostProcessingPipeline,
        outputSink: any PipelineOutputSink,
        contextProvider: any PipelineContextProviding,
        persistenceHandler: (@Sendable (TranscriptEntry) async throws -> Void)?
    ) {
        let initialContext = contextProvider.currentContext()
        self.capture = capture
        self.transcriber = transcriber
        self.logger = logger
        self.postProcessingPipeline = postProcessingPipeline
        self.outputSink = outputSink
        self.contextProvider = contextProvider
        self.persistenceHandler = persistenceHandler
        self.activeContext = initialContext
        self.currentSnapshot = PipelineSnapshot(context: initialContext)
    }

    public func toggleCapture() async {
        switch currentSnapshot.sessionState {
        case .idle:
            await startRecording()
        case .recording, .holdRecording:
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
        case .idle:
            await startHoldRecording()
        case .error:
            publish { snapshot in
                snapshot.sessionState = .idle
                snapshot.activeStage = nil
                snapshot.transcriptProgress = nil
                snapshot.recordingDuration = nil
            }
            await startHoldRecording()
        case .recording, .holdRecording, .transcribing:
            logger.info("Ignored hold-start while session is not .idle")
        }
    }

    public func prepareTranscriber() async throws {
        try await transcriber.prepare()
    }

    public func snapshot() -> PipelineSnapshot {
        currentSnapshot
    }

    public func snapshotStream() -> AsyncStream<PipelineSnapshot> {
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

    private func publish(_ mutation: (inout PipelineSnapshot) -> Void) {
        mutation(&currentSnapshot)
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

            // Kick off prepare BEFORE publishing `.recording` so the
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
                snapshot.sessionState = .recording
                snapshot.activeStage = .capture
                snapshot.transcriptProgress = nil
                snapshot.recordingDuration = .zero
                snapshot.context = activeContext
            }

            captureTask = Task { [weak self] in
                await self?.consumeCaptureStream(stream)
            }
        } catch {
            handleStageFailure(makeStageFailure(stage: .capture, error: error, fallback: .audioEngineFailure))
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

        publish { snapshot in
            snapshot.sessionState = .holdRecording
            snapshot.activeStage = .capture
            snapshot.transcriptProgress = nil
            snapshot.recordingDuration = .zero
            snapshot.context = activeContext
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
                snapshot.sessionState = .error(.recordingTooShort)
                snapshot.activeStage = .transcription
                snapshot.recordingDuration = bufferedDuration
            }
            return
        }

        publish { snapshot in
            snapshot.sessionState = .transcribing
            snapshot.activeStage = .transcription
            snapshot.recordingDuration = bufferedDuration
        }

        do {
            let rawResult = try await runTranscription(stream: makeReplayStream(from: replayBuffers))
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
                snapshot.context = activeContext
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
                snapshot.sessionState = .idle
                snapshot.activeStage = nil
                snapshot.transcriptProgress = cleanedProgress
                snapshot.lastCompletedResult = finalResult
                snapshot.recordingDuration = rawResult.audioDuration
                snapshot.context = activeContext
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
        sourceStage: PipelineStageID
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
        do {
            for try await buffer in stream {
                bufferedAudio.append(buffer)
                publish { snapshot in
                    snapshot.recordingDuration = (snapshot.recordingDuration ?? .zero) + buffer.duration
                }
            }
        } catch {
            handleStageFailure(makeStageFailure(stage: .capture, error: error, fallback: .audioEngineFailure))
        }
    }

    private func handleStageFailure(_ failure: PipelineStageFailure) {
        latestStageFailure = failure
        publish { snapshot in
            snapshot.sessionState = .error(failure.mappedError)
            snapshot.activeStage = failure.stage
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
        stage: PipelineStageID,
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
        if let describable = error as? any CustomStringConvertible {
            return describable.description
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
