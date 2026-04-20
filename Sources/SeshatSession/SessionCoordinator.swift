import Foundation
import os.signpost
import SeshatCore

public actor SessionCoordinator {
    private let capture: any AudioCapturing
    private let fixedTranscriber: (any Transcribing)?
    private let modelService: (any ModelService)?
    private let transcriberProvider: (any ModelBoundTranscriberProviding)?
    private let transcriptStore: SQLiteTranscriptStore?
    private let logger: SeshatLogger
    private let postProcessor = PostProcessor()
    private let signposter = OSSignposter(subsystem: SeshatLogger.subsystem, category: "prepare")
    private let downloadProgressBroadcaster = SessionDownloadProgressBroadcaster()
    private let pipeline: SessionPipelineOrchestrator
    private let pipelineTranscriber: CoordinatorPipelineTranscriber

    private var currentState: SessionState = .idle
    private var mostRecentResult: TranscriptionResult?
    private var stateContinuations: [UUID: AsyncStream<SessionState>.Continuation] = [:]
    private var bufferedAudio: [PCMBuffer] = []
    private var captureTask: Task<Void, Never>?
    private var downloadProgressObservationTask: Task<Void, Never>?
    private var recordingSessionTranscriber: (any Transcribing)?

    // Step 2.10: additive audio-level multiplexing. Subscribes to the capture
    // service's per-session level stream and fans values out to all
    // registered consumers so SwiftUI surfaces can bind directly without
    // holding a reference to the capture actor. Current value is cached so
    // late subscribers get a starting sample.
    private var audioLevelContinuations: [UUID: AsyncStream<Float>.Continuation] = [:]
    private var currentAudioLevel: Float = 0.0
    private var audioLevelTask: Task<Void, Never>?

    public init(
        capture: any AudioCapturing,
        transcriber: any Transcribing,
        logger: SeshatLogger,
        transcriptStore: SQLiteTranscriptStore? = nil
    ) {
        let pipelineTranscriber = CoordinatorPipelineTranscriber(
            fixedTranscriber: transcriber,
            logger: logger
        )
        self.capture = capture
        self.fixedTranscriber = transcriber
        self.modelService = nil
        self.transcriberProvider = nil
        self.transcriptStore = transcriptStore
        self.logger = logger
        self.pipelineTranscriber = pipelineTranscriber
        self.pipeline = Self.makePipeline(
            capture: capture,
            pipelineTranscriber: pipelineTranscriber,
            transcriptStore: transcriptStore,
            logger: logger
        )
        Self.startPipelineObservers(
            owner: self,
            pipeline: self.pipeline,
            pipelineTranscriber: self.pipelineTranscriber,
            broadcaster: self.downloadProgressBroadcaster
        )
    }

    public init(
        capture: any AudioCapturing,
        modelService: any ModelService,
        transcriberProvider: any ModelBoundTranscriberProviding,
        logger: SeshatLogger,
        transcriptStore: SQLiteTranscriptStore? = nil
    ) {
        let pipelineTranscriber = CoordinatorPipelineTranscriber(
            modelService: modelService,
            transcriberProvider: transcriberProvider,
            logger: logger
        )
        self.capture = capture
        self.fixedTranscriber = nil
        self.modelService = modelService
        self.transcriberProvider = transcriberProvider
        self.transcriptStore = transcriptStore
        self.logger = logger
        self.pipelineTranscriber = pipelineTranscriber
        self.pipeline = Self.makePipeline(
            capture: capture,
            pipelineTranscriber: pipelineTranscriber,
            transcriptStore: transcriptStore,
            logger: logger
        )
        Self.startPipelineObservers(
            owner: self,
            pipeline: self.pipeline,
            pipelineTranscriber: self.pipelineTranscriber,
            broadcaster: self.downloadProgressBroadcaster
        )
    }

    public func toggle() async {
        await pipeline.toggleCapture()
        let snapshot = await pipeline.snapshot()
        applyPipelineSnapshot(snapshot)
    }

    public func state() -> SessionState {
        currentState
    }

    public func stateStream() -> AsyncStream<SessionState> {
        let id = UUID()

        return AsyncStream { continuation in
            continuation.yield(self.currentState)
            self.stateContinuations[id] = continuation
            continuation.onTermination = { [self] _ in
                Task {
                    await self.removeContinuation(id: id)
                }
            }
        }
    }

    /// Multiplexed audio-level stream (phase-2 step 2.10). Yields the latest
    /// cached level on subscription and every subsequent level republished
    /// from the capture service while recording is live. Values are
    /// normalized `[0, 1]`. Stream stays open across start/stop cycles —
    /// the coordinator resubscribes to the capture's level stream on every
    /// new recording.
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

    public func lastResult() -> TranscriptionResult? {
        mostRecentResult
    }

    /// Idempotent passthrough for eager model preparation; `prepare()` coalesces repeated calls.
    public func prepareTranscriber() async throws {
        let intervalName: StaticString = "SessionCoordinator.prepareTranscriber"
        let state = signposter.beginInterval(intervalName)
        defer { signposter.endInterval(intervalName, state) }
        try await pipeline.prepareTranscriber()
    }

    public func modelDownloadProgress() -> AsyncStream<ModelDownloadProgress> {
        downloadProgressBroadcaster.stream()
    }

    private func removeContinuation(id: UUID) {
        stateContinuations[id] = nil
    }

    private func removeAudioLevelContinuation(id: UUID) {
        audioLevelContinuations[id] = nil
    }

    private static func makePipeline(
        capture: any AudioCapturing,
        pipelineTranscriber: CoordinatorPipelineTranscriber,
        transcriptStore: SQLiteTranscriptStore?,
        logger: SeshatLogger
    ) -> SessionPipelineOrchestrator {
        SessionPipelineOrchestrator(
            capture: CoordinatorPipelineCapture(
                base: capture,
                pipelineTranscriber: pipelineTranscriber
            ),
            transcriber: pipelineTranscriber,
            logger: logger,
            postProcessingPipeline: CoordinatorPostProcessingPipeline(),
            outputSink: CoordinatorPipelineOutputSink(),
            contextProvider: CoordinatorPipelineContextProvider(),
            persistenceHandler: makePersistenceHandler(
                transcriptStore: transcriptStore,
                logger: logger
            )
        )
    }

    private static func makePersistenceHandler(
        transcriptStore: SQLiteTranscriptStore?,
        logger: SeshatLogger
    ) -> (@Sendable (TranscriptEntry) async throws -> Void)? {
        guard let transcriptStore else {
            return nil
        }

        return { entry in
            do {
                try await transcriptStore.append(entry)
            } catch {
                logger.error("Failed to persist transcript to SQLiteTranscriptStore", error: error)
            }
        }
    }

    private static func startPipelineObservers(
        owner: SessionCoordinator,
        pipeline: SessionPipelineOrchestrator,
        pipelineTranscriber: CoordinatorPipelineTranscriber,
        broadcaster: SessionDownloadProgressBroadcaster
    ) {
        Task { [weak owner, pipeline] in
            let stream = await pipeline.snapshotStream()
            for await snapshot in stream {
                guard let owner else {
                    return
                }
                await owner.applyPipelineSnapshot(snapshot)
            }
        }

        Task { [weak owner, pipeline] in
            let stream = await pipeline.audioLevelStream()
            for await level in stream {
                guard let owner else {
                    return
                }
                await owner.publishAudioLevel(level)
            }
        }

        Task {
            let stream = await pipelineTranscriber.modelDownloadProgress()
            for await progress in stream {
                broadcaster.update(progress)
            }
        }
    }

    private func publish(_ state: SessionState) {
        currentState = state
        for continuation in stateContinuations.values {
            continuation.yield(state)
        }
    }

    /// Update the cached audio level and fan out to all subscribers.
    private func publishAudioLevel(_ level: Float) {
        currentAudioLevel = level
        for continuation in audioLevelContinuations.values {
            continuation.yield(level)
        }
    }

    private func applyPipelineSnapshot(_ snapshot: PipelineSnapshot) {
        mostRecentResult = snapshot.lastCompletedResult
        if currentState != snapshot.sessionState {
            publish(snapshot.sessionState)
        }
    }

    private func startRecording() async {
        bufferedAudio.removeAll(keepingCapacity: true)

        do {
            let stream = try await capture.start()
            let transcriber = await resolveRecordingSessionTranscriber()
            // Step 2.10: subscribe to capture's level stream before flipping
            // to .recording so any early emissions reach UI consumers.
            let levelStream = await capture.audioLevelStream()
            audioLevelTask?.cancel()
            audioLevelTask = Task { [weak self] in
                for await level in levelStream {
                    await self?.publishAudioLevel(level)
                }
                // When the capture's level stream ends, fall back to silence
                // so a subsequent recording starts from 0 rather than the
                // last loud sample.
                await self?.publishAudioLevel(0.0)
            }

            publish(.recording)
            prepareTranscriberInBackground(using: transcriber)
            captureTask = Task {
                await self.consumeCaptureStream(stream)
            }
        } catch {
            publish(.error(map(error, default: .audioEngineFailure)))
        }
    }

    private func stopRecordingAndTranscribe() async {
        await capture.stop()
        await captureTask?.value
        captureTask = nil

        // Step 2.10: drain the level-forwarding task so the coordinator's
        // cached level settles to 0 before the UI observes .transcribing.
        await audioLevelTask?.value
        audioLevelTask = nil
        defer {
            recordingSessionTranscriber = nil
        }

        if case .error = currentState {
            logger.info("Capture stream failed while stop was in flight; preserving error state")
            bufferedAudio.removeAll(keepingCapacity: true)
            return
        }

        let replayBuffers = bufferedAudio
        bufferedAudio.removeAll(keepingCapacity: true)
        let transcriber = await transcriberForStopPath()

        // FluidAudio requires at least 1 second of 16 kHz audio; feeding
        // shorter buffers surfaces as "Invalid audio data" mid-transcribe
        // which then routes to `.error` → pill vanishes silently. Guard
        // at the coordinator layer so the user sees a "too short" signal
        // instead of a disappearing pill.
        let bufferedDuration = replayBuffers.reduce(Duration.zero) { $0 + $1.duration }
        if bufferedDuration < .milliseconds(1_000) {
            logger.info("Recording too short (\(bufferedDuration)); skipping transcription")
            publish(.error(.recordingTooShort))
            return
        }

        publish(.transcribing)

        do {
            let raw = try await transcriber.transcribe(stream: makeReplayStream(from: replayBuffers))
            let cleanedText = postProcessor.clean(raw.text)
            mostRecentResult = TranscriptionResult(
                text: cleanedText,
                segments: raw.segments,
                audioDuration: raw.audioDuration,
                processingDuration: raw.processingDuration
            )
            await persistTranscript(
                text: cleanedText,
                audioDuration: raw.audioDuration,
                processingDuration: raw.processingDuration
            )
            publish(.idle)
        } catch {
            publish(.error(map(error, default: .transcriptionFailure)))
        }
    }

    private func persistTranscript(
        text: String,
        audioDuration: Duration,
        processingDuration: Duration
    ) async {
        guard let transcriptStore else {
            return
        }

        let entry = TranscriptEntry(
            id: UUID(),
            timestamp: Date(),
            text: text,
            audioDuration: Self.seconds(from: audioDuration),
            processingDuration: Self.seconds(from: processingDuration)
        )

        do {
            try await transcriptStore.append(entry)
        } catch {
            logger.error("Failed to persist transcript to SQLiteTranscriptStore", error: error)
        }
    }

    private static func seconds(from duration: Duration) -> TimeInterval {
        let components = duration.components
        return TimeInterval(components.seconds)
            + TimeInterval(components.attoseconds) / 1_000_000_000_000_000_000
    }

    private func consumeCaptureStream(_ stream: AsyncThrowingStream<PCMBuffer, Error>) async {
        do {
            for try await buffer in stream {
                bufferedAudio.append(buffer)
            }
        } catch {
            publish(.error(map(error, default: .audioEngineFailure)))
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

    private func map(_ error: any Error, default fallback: SeshatError) -> SeshatError {
        if let seshatError = error as? SeshatError {
            return seshatError
        }

        logger.error("Mapped underlying error to shared contract", error: error)
        return fallback
    }

    private func prepareTranscriberInBackground(using transcriber: any Transcribing) {
        let logger = logger

        Task.detached(priority: .background) {
            do {
                try await transcriber.prepare()
            } catch is CancellationError {
                return
            } catch {
                logger.error("Background transcriber preparation failed", error: error)
            }
        }
    }

    private func resolvedTranscriberForPreparation() async -> any Transcribing {
        if let recordingSessionTranscriber {
            observeDownloadProgress(for: recordingSessionTranscriber)
            return recordingSessionTranscriber
        }

        return await resolvedActiveTranscriber()
    }

    private func resolveRecordingSessionTranscriber() async -> any Transcribing {
        if let fixedTranscriber {
            recordingSessionTranscriber = fixedTranscriber
            observeDownloadProgress(for: fixedTranscriber)
            return fixedTranscriber
        }

        let descriptor = await activeVoiceModel()
        let transcriber = resolvedModelBoundTranscriber(for: descriptor)
        recordingSessionTranscriber = transcriber
        observeDownloadProgress(for: transcriber)
        return transcriber
    }

    private func transcriberForStopPath() async -> any Transcribing {
        if let recordingSessionTranscriber {
            return recordingSessionTranscriber
        }

        return await resolvedActiveTranscriber()
    }

    private func resolvedActiveTranscriber() async -> any Transcribing {
        if let fixedTranscriber {
            observeDownloadProgress(for: fixedTranscriber)
            return fixedTranscriber
        }

        let descriptor = await activeVoiceModel()
        let transcriber = resolvedModelBoundTranscriber(for: descriptor)
        observeDownloadProgress(for: transcriber)
        return transcriber
    }

    private func activeVoiceModel() async -> ModelDescriptor {
        guard let modelService else {
            preconditionFailure("SessionCoordinator model-service path requires a ModelService")
        }

        return await MainActor.run {
            modelService.activeDescriptor.voiceModel
        }
    }

    private func resolvedModelBoundTranscriber(
        for descriptor: ModelDescriptor
    ) -> any Transcribing {
        guard let transcriberProvider else {
            preconditionFailure("SessionCoordinator model-service path requires a transcriber provider")
        }

        return transcriberProvider.transcriber(for: descriptor)
    }

    private func observeDownloadProgress(for transcriber: any Transcribing) {
        downloadProgressObservationTask?.cancel()
        let broadcaster = downloadProgressBroadcaster

        downloadProgressObservationTask = Task {
            for await progress in transcriber.modelDownloadProgress() {
                if Task.isCancelled {
                    return
                }

                broadcaster.update(progress)
            }
        }
    }
}

private struct CoordinatorPipelineCapture: AudioCapturing {
    private let base: any AudioCapturing
    private let pipelineTranscriber: CoordinatorPipelineTranscriber

    init(
        base: any AudioCapturing,
        pipelineTranscriber: CoordinatorPipelineTranscriber
    ) {
        self.base = base
        self.pipelineTranscriber = pipelineTranscriber
    }

    func start() async throws -> AsyncThrowingStream<PCMBuffer, Error> {
        let stream = try await base.start()
        await pipelineTranscriber.beginRecordingSession()
        return stream
    }

    func stop() async {
        await base.stop()
    }

    func audioLevelStream() async -> AsyncStream<Float> {
        await base.audioLevelStream()
    }
}

private actor CoordinatorPipelineTranscriber: Transcribing {
    private let fixedTranscriber: (any Transcribing)?
    private let modelService: (any ModelService)?
    private let transcriberProvider: (any ModelBoundTranscriberProviding)?
    private let logger: SeshatLogger
    private let progressBroadcaster = SessionDownloadProgressBroadcaster()

    private var recordingSessionTranscriber: (any Transcribing)?
    private var progressObservationTask: Task<Void, Never>?

    init(
        fixedTranscriber: any Transcribing,
        logger: SeshatLogger
    ) {
        self.fixedTranscriber = fixedTranscriber
        self.modelService = nil
        self.transcriberProvider = nil
        self.logger = logger
    }

    init(
        modelService: any ModelService,
        transcriberProvider: any ModelBoundTranscriberProviding,
        logger: SeshatLogger
    ) {
        self.fixedTranscriber = nil
        self.modelService = modelService
        self.transcriberProvider = transcriberProvider
        self.logger = logger
    }

    func beginRecordingSession() async {
        let transcriber = await resolveRecordingSessionTranscriber()
        observeDownloadProgress(for: transcriber)
    }

    func prepare() async throws {
        let transcriber = await resolvedTranscriberForPreparation()
        try await transcriber.prepare()
    }

    nonisolated func modelDownloadProgress() -> AsyncStream<ModelDownloadProgress> {
        progressBroadcaster.stream()
    }

    func transcribe(_ audio: PCMBuffer) async throws -> TranscriptionResult {
        let transcriber = await transcriberForStopPath()
        defer {
            recordingSessionTranscriber = nil
        }
        return try await transcriber.transcribe(audio)
    }

    func transcribe(stream: AsyncThrowingStream<PCMBuffer, Error>) async throws -> TranscriptionResult {
        let transcriber = await transcriberForStopPath()
        defer {
            recordingSessionTranscriber = nil
        }
        return try await transcriber.transcribe(stream: stream)
    }

    private func resolvedTranscriberForPreparation() async -> any Transcribing {
        if let recordingSessionTranscriber {
            observeDownloadProgress(for: recordingSessionTranscriber)
            return recordingSessionTranscriber
        }

        return await resolvedActiveTranscriber()
    }

    private func resolveRecordingSessionTranscriber() async -> any Transcribing {
        if let fixedTranscriber {
            recordingSessionTranscriber = fixedTranscriber
            observeDownloadProgress(for: fixedTranscriber)
            return fixedTranscriber
        }

        let descriptor = await activeVoiceModel()
        let transcriber = resolvedModelBoundTranscriber(for: descriptor)
        recordingSessionTranscriber = transcriber
        observeDownloadProgress(for: transcriber)
        return transcriber
    }

    private func transcriberForStopPath() async -> any Transcribing {
        if let recordingSessionTranscriber {
            return recordingSessionTranscriber
        }

        return await resolvedActiveTranscriber()
    }

    private func resolvedActiveTranscriber() async -> any Transcribing {
        if let fixedTranscriber {
            observeDownloadProgress(for: fixedTranscriber)
            return fixedTranscriber
        }

        let descriptor = await activeVoiceModel()
        let transcriber = resolvedModelBoundTranscriber(for: descriptor)
        observeDownloadProgress(for: transcriber)
        return transcriber
    }

    private func activeVoiceModel() async -> ModelDescriptor {
        guard let modelService else {
            preconditionFailure("SessionCoordinator model-service path requires a ModelService")
        }

        return await MainActor.run {
            modelService.activeDescriptor.voiceModel
        }
    }

    private func resolvedModelBoundTranscriber(
        for descriptor: ModelDescriptor
    ) -> any Transcribing {
        guard let transcriberProvider else {
            preconditionFailure("SessionCoordinator model-service path requires a transcriber provider")
        }

        return transcriberProvider.transcriber(for: descriptor)
    }

    private func observeDownloadProgress(for transcriber: any Transcribing) {
        progressObservationTask?.cancel()
        let broadcaster = progressBroadcaster

        progressObservationTask = Task {
            for await progress in transcriber.modelDownloadProgress() {
                if Task.isCancelled {
                    return
                }

                broadcaster.update(progress)
            }
        }
    }
}

private struct CoordinatorPostProcessingPipeline: PostProcessingPipeline {
    private let postProcessor = PostProcessor()

    func run(_ text: String, context: PostProcessingContext) async throws -> String {
        postProcessor.clean(text)
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

private final class SessionDownloadProgressBroadcaster: @unchecked Sendable {
    private let lock = NSLock()
    private var continuations: [UUID: AsyncStream<ModelDownloadProgress>.Continuation] = [:]
    private var snapshot = ModelDownloadProgress(
        phase: .idle,
        fractionCompleted: 0,
        receivedBytes: 0,
        expectedBytes: nil
    )

    func stream() -> AsyncStream<ModelDownloadProgress> {
        AsyncStream { continuation in
            let identifier = UUID()
            let initial = lock.withLock { () -> ModelDownloadProgress in
                continuations[identifier] = continuation
                return snapshot
            }

            continuation.onTermination = { [weak self] _ in
                guard let self else { return }
                _ = self.lock.withLock {
                    self.continuations.removeValue(forKey: identifier)
                }
            }
            continuation.yield(initial)
        }
    }

    func update(_ snapshot: ModelDownloadProgress) {
        let continuations = lock.withLock { () -> [AsyncStream<ModelDownloadProgress>.Continuation] in
            self.snapshot = snapshot
            return Array(self.continuations.values)
        }

        for continuation in continuations {
            continuation.yield(snapshot)
        }
    }
}
