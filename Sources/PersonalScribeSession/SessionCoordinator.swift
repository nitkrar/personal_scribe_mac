import Foundation
import os.signpost
import PersonalScribeCore
import PersonalScribeVAD

public actor SessionCoordinator {
    private let capture: any AudioCapturing
    private let fixedTranscriber: (any Transcribing)?
    private let modelService: (any ModelService)?
    private let transcriberProvider: (any ModelBoundTranscriberProviding)?
    private let transcriptRepository: TranscriptRepository?
    private let logger: PersonalScribeLogger
    private let signposter = OSSignposter(subsystem: PersonalScribeLogger.subsystem, category: "prepare")
    private let pipeline: SessionPipelineOrchestrator
    private let pipelineTranscriber: CoordinatorPipelineTranscriber

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
        transcriptRepository: TranscriptRepository? = nil,
        vadProvider: (any VadProviding)? = nil,
        vadPreferences: (any VadPreferencesReading)? = nil
    ) {
        let pipelineTranscriber = CoordinatorPipelineTranscriber(
            fixedTranscriber: transcriber,
            logger: logger
        )
        self.capture = capture
        self.fixedTranscriber = transcriber
        self.modelService = nil
        self.transcriberProvider = nil
        self.transcriptRepository = transcriptRepository
        self.logger = logger
        self.pipelineTranscriber = pipelineTranscriber
        self.pipeline = Self.makePipeline(
            capture: capture,
            pipelineTranscriber: pipelineTranscriber,
            transcriptRepository: transcriptRepository,
            logger: logger,
            vadProvider: vadProvider,
            vadPreferences: vadPreferences
        )
        Task { [weak self] in
            await self?.installAutoStopHandler()
        }
    }

    public init(
        capture: any AudioCapturing,
        modelService: any ModelService,
        transcriberProvider: any ModelBoundTranscriberProviding,
        logger: PersonalScribeLogger,
        transcriptRepository: TranscriptRepository? = nil,
        vadProvider: (any VadProviding)? = nil,
        vadPreferences: (any VadPreferencesReading)? = nil
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
        self.transcriptRepository = transcriptRepository
        self.logger = logger
        self.pipelineTranscriber = pipelineTranscriber
        self.pipeline = Self.makePipeline(
            capture: capture,
            pipelineTranscriber: pipelineTranscriber,
            transcriptRepository: transcriptRepository,
            logger: logger,
            vadProvider: vadProvider,
            vadPreferences: vadPreferences
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
        case .recording, .holdRecording:
            await performStop()
        case .transcribing, .error:
            await performToggle()
        case .completed:
            await performStart()
        }
    }

    public func startIfIdle() async {
        guard await currentDisplayState() == .idle else {
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

        await performHoldStart()
    }

    public func stopIfRecording() async {
        guard await currentDisplayState() == .recording else {
            return
        }

        await performStop()
    }

    /// Mode-agnostic stop. Transitions either `.recording` or
    /// `.holdRecording` into `.transcribing` via the normal pipeline
    /// stop path. Preferred entry point for hold-release, VAD auto-stop
    /// (#046), and app-quit cleanup — those callers don't know or care
    /// how the session started. No-op from `.idle`, `.transcribing`,
    /// or `.error`.
    public func stopIfActive() async {
        switch await currentDisplayState() {
        case .recording, .holdRecording:
            await performStop()
        case .idle, .completed, .transcribing, .error:
            return
        }
    }

    /// Mode-agnostic true-cancel. Transitions either `.recording` or
    /// `.holdRecording` directly to `.idle` via `pipeline.cancelCapture()`
    /// — buffered audio is discarded, transcribe + output stages are
    /// skipped entirely. Preferred entry point for Esc and the pill ✕
    /// button (#002). No-op from `.idle`, `.transcribing`, or `.error`.
    public func cancelIfActive() async {
        switch await currentDisplayState() {
        case .recording, .holdRecording:
            await performCancel()
        case .idle, .completed, .transcribing, .error:
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

    /// Idempotent passthrough for eager model preparation; `prepare()` coalesces repeated calls.
    public func prepareTranscriber() async throws {
        let intervalName: StaticString = "SessionCoordinator.prepareTranscriber"
        let state = signposter.beginInterval(intervalName)
        defer { signposter.endInterval(intervalName, state) }
        try await pipeline.prepareTranscriber()
    }

    public func modelDownloadProgress() async -> AsyncStream<ModelDownloadProgress> {
        await pipeline.modelDownloadProgress()
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
    }

    private func performHoldStart() async {
        await startAudioLevelRelayIfNeeded()
        await pipeline.startHoldCapture()
    }

    private func performCancel() async {
        await pipeline.cancelCapture()
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
        transcriptRepository: TranscriptRepository?,
        logger: PersonalScribeLogger,
        vadProvider: (any VadProviding)?,
        vadPreferences: (any VadPreferencesReading)?
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
                transcriptRepository: transcriptRepository,
                logger: logger
            ),
            vadProvider: vadProvider,
            vadPreferences: vadPreferences
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

    private static func displayState(for state: SessionState) -> SessionState {
        switch state {
        case .completed:
            return .idle
        case .idle, .recording, .holdRecording, .transcribing, .error:
            return state
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
