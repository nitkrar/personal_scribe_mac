import Foundation
import os.signpost
import PersonalScribeCore

public actor SessionCoordinator {
    private let capture: any AudioCapturing
    private let fixedTranscriber: (any Transcribing)?
    private let modelService: (any ModelService)?
    private let transcriberProvider: (any ModelBoundTranscriberProviding)?
    private let transcriptStore: SQLiteTranscriptStore?
    private let logger: PersonalScribeLogger
    private let signposter = OSSignposter(subsystem: PersonalScribeLogger.subsystem, category: "prepare")
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
        logger: PersonalScribeLogger,
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
        logger: PersonalScribeLogger,
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
        switch currentState {
        case .idle:
            await performStart()
        case .recording:
            await performStop()
        case .transcribing, .error:
            await performToggle()
        }
    }

    public func startIfIdle() async {
        guard currentState == .idle else {
            return
        }

        await performStart()
    }

    public func stopIfRecording() async {
        guard currentState == .recording else {
            return
        }

        await performStop()
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

    private func performStart() async {
        await performToggle()
    }

    private func performStop() async {
        await performToggle()
    }

    private func performToggle() async {
        await startAudioLevelRelayIfNeeded()
        await pipeline.toggleCapture()
        await refreshFromPipelineSnapshot()
    }

    private func refreshFromPipelineSnapshot() async {
        let snapshot = await pipeline.snapshot()
        applyPipelineSnapshot(snapshot)
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
        capture: any AudioCapturing,
        pipelineTranscriber: CoordinatorPipelineTranscriber,
        transcriptStore: SQLiteTranscriptStore?,
        logger: PersonalScribeLogger
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
        logger: PersonalScribeLogger
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
    private let logger: PersonalScribeLogger
    private let progressBroadcaster = SessionDownloadProgressBroadcaster()

    private var recordingSessionTranscriber: (any Transcribing)?
    private var progressObservationTask: Task<Void, Never>?

    init(
        fixedTranscriber: any Transcribing,
        logger: PersonalScribeLogger
    ) {
        self.fixedTranscriber = fixedTranscriber
        self.modelService = nil
        self.transcriberProvider = nil
        self.logger = logger
    }

    init(
        modelService: any ModelService,
        transcriberProvider: any ModelBoundTranscriberProviding,
        logger: PersonalScribeLogger
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
