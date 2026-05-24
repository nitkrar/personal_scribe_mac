import Foundation
import PersonalScribeCore

public protocol SessionGateProviding: Sendable {
    func snapshot() async -> SessionSnapshot
    func snapshotStream() async -> AsyncStream<SessionSnapshot>
}

public actor OfflineTranscriptionCoordinator {
    public enum JobStatus: Sendable, Equatable {
        case queued
        case inFlight(progress: Double)
        case completed(transcriptID: UUID)
        case failed(reason: FailureReason)
        case cancelled
    }

    public enum FailureReason: Sendable, Equatable {
        case audioMissing
        case modelNotAvailable
        case conversionFailed
        case transcriptionFailed
        case other(String)
    }

    public enum RecipeOverride: Sendable, Equatable {
        case fixedDictation
    }

    public struct Job: Sendable, Equatable {
        public let id: UUID
        public let url: URL
        public let sourceFilename: String
        public let descriptorID: String
        public let diarize: Bool
        public let recipeOverride: RecipeOverride?
        public let enqueuedAt: Date
        public let status: JobStatus

        public init(
            id: UUID,
            url: URL,
            sourceFilename: String,
            descriptorID: String,
            diarize: Bool,
            recipeOverride: RecipeOverride?,
            enqueuedAt: Date,
            status: JobStatus
        ) {
            self.id = id
            self.url = url
            self.sourceFilename = sourceFilename
            self.descriptorID = descriptorID
            self.diarize = diarize
            self.recipeOverride = recipeOverride
            self.enqueuedAt = enqueuedAt
            self.status = status
        }
    }

    private let activeASRDescriptor: @Sendable () async -> ModelDescriptor?
    private let descriptorByID: @Sendable (String) async -> ModelDescriptor?
    private let processorProvider: any ModelBoundProcessorProviding
    private let transcriptRepository: TranscriptRepository
    private let sessionGate: any SessionGateProviding
    private let fileSourceAudioStream: any FileSourceAudioStreaming
    private let postProcessingPipeline: any PostProcessingPipeline
    private let recordingsDirectory: @Sendable () throws -> URL
    private let now: @Sendable () -> Date
    private let diarizationSensitivity: SpeakerSeparationSensitivity
    private let logger: PersonalScribeLogger

    private var jobs: [Job] = []
    private var snapshotContinuations: [UUID: AsyncStream<[Job]>.Continuation] = [:]
    private var processingTask: Task<Void, Never>?
    private var activeJobID: UUID?
    private var sessionIsIdle = false

    @MainActor
    public init(
        modelService: ActiveModelService,
        processorProvider: any ModelBoundProcessorProviding,
        transcriptRepository: TranscriptRepository,
        sessionGate: any SessionGateProviding,
        fileSourceAudioStream: any FileSourceAudioStreaming = FileSourceAudioStream(),
        postProcessingPipeline: any PostProcessingPipeline = DefaultPostProcessingPipeline(),
        recordingsDirectory: @escaping @Sendable () throws -> URL = { try AppConfig.recordingsDirectory() },
        now: @escaping @Sendable () -> Date = Date.init,
        diarizationSensitivity: SpeakerSeparationSensitivity = .balanced,
        logger: PersonalScribeLogger
    ) {
        self.init(
            activeASRDescriptor: {
                await MainActor.run {
                    modelService.activeDescriptor(for: .asr)
                }
            },
            descriptorByID: { descriptorID in
                await MainActor.run {
                    modelService.registeredModels.first { $0.id == descriptorID }
                }
            },
            processorProvider: processorProvider,
            transcriptRepository: transcriptRepository,
            sessionGate: sessionGate,
            fileSourceAudioStream: fileSourceAudioStream,
            postProcessingPipeline: postProcessingPipeline,
            recordingsDirectory: recordingsDirectory,
            now: now,
            diarizationSensitivity: diarizationSensitivity,
            logger: logger
        )
    }

    init(
        activeASRDescriptor: @escaping @Sendable () async -> ModelDescriptor?,
        descriptorByID: @escaping @Sendable (String) async -> ModelDescriptor?,
        processorProvider: any ModelBoundProcessorProviding,
        transcriptRepository: TranscriptRepository,
        sessionGate: any SessionGateProviding,
        fileSourceAudioStream: any FileSourceAudioStreaming = FileSourceAudioStream(),
        postProcessingPipeline: any PostProcessingPipeline = DefaultPostProcessingPipeline(),
        recordingsDirectory: @escaping @Sendable () throws -> URL = { try AppConfig.recordingsDirectory() },
        now: @escaping @Sendable () -> Date = Date.init,
        diarizationSensitivity: SpeakerSeparationSensitivity = .balanced,
        logger: PersonalScribeLogger
    ) {
        self.activeASRDescriptor = activeASRDescriptor
        self.descriptorByID = descriptorByID
        self.processorProvider = processorProvider
        self.transcriptRepository = transcriptRepository
        self.sessionGate = sessionGate
        self.fileSourceAudioStream = fileSourceAudioStream
        self.postProcessingPipeline = postProcessingPipeline
        self.recordingsDirectory = recordingsDirectory
        self.now = now
        self.diarizationSensitivity = diarizationSensitivity
        self.logger = logger
        Task { [weak self] in
            await self?.observeSessionGate()
        }
    }

    deinit {
        processingTask?.cancel()
        for continuation in snapshotContinuations.values {
            continuation.finish()
        }
    }

    public func enqueueFile(
        url: URL,
        descriptorID: String,
        diarize: Bool
    ) -> UUID {
        let resolvedURL = url.standardizedFileURL
        let job = Job(
            id: UUID(),
            url: resolvedURL,
            sourceFilename: persistedAudioFilename(for: resolvedURL),
            descriptorID: descriptorID,
            diarize: diarize,
            recipeOverride: nil,
            enqueuedAt: now(),
            status: .queued
        )

        jobs.append(job)
        publishSnapshot()
        startNextJobIfPossible()
        return job.id
    }

    public func reTranscribe(sourceFilename: String) async -> UUID {
        let resolvedURL: URL
        do {
            resolvedURL = try resolveSourceURL(from: sourceFilename)
        } catch {
            return enqueueImmediatelyFailedJob(
                url: placeholderURL(for: sourceFilename),
                sourceFilename: sourceFilename,
                descriptorID: "",
                recipeOverride: .fixedDictation,
                reason: .other(String(describing: error))
            )
        }

        if let existingID = existingQueuedOrInFlightJobID(forResolvedURL: resolvedURL) {
            return existingID
        }

        guard FileManager.default.fileExists(atPath: resolvedURL.path) else {
            let id = enqueueImmediatelyFailedJob(
                url: resolvedURL,
                sourceFilename: sourceFilename,
                descriptorID: "",
                recipeOverride: .fixedDictation,
                reason: .audioMissing
            )
            await nullifyMissingAudioFilename(sourceFilename)
            return id
        }

        guard let descriptor = await activeASRDescriptor(), descriptor.kind == .asr else {
            return enqueueImmediatelyFailedJob(
                url: resolvedURL,
                sourceFilename: sourceFilename,
                descriptorID: "",
                recipeOverride: .fixedDictation,
                reason: .modelNotAvailable
            )
        }

        let job = Job(
            id: UUID(),
            url: resolvedURL,
            sourceFilename: sourceFilename,
            descriptorID: descriptor.id,
            diarize: false,
            recipeOverride: .fixedDictation,
            enqueuedAt: now(),
            status: .queued
        )

        jobs.append(job)
        publishSnapshot()
        startNextJobIfPossible()
        return job.id
    }

    public func cancelJob(id: UUID) {
        guard activeJobID == id else {
            return
        }
        processingTask?.cancel()
    }

    public func dequeueJob(id: UUID) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else {
            return
        }
        guard jobs[index].status == .queued else {
            return
        }
        jobs.remove(at: index)
        publishSnapshot()
    }

    public func snapshot() -> [Job] {
        jobs
    }

    public func snapshotStream() -> AsyncStream<[Job]> {
        let id = UUID()
        let snapshot = jobs

        return AsyncStream { continuation in
            self.snapshotContinuations[id] = continuation
            continuation.onTermination = { [weak self] _ in
                Task {
                    await self?.removeSnapshotContinuation(id)
                }
            }
            continuation.yield(snapshot)
        }
    }
}

public extension SessionCoordinator {
    nonisolated func offlineTranscriptionSessionGate() -> any SessionGateProviding {
        self
    }
}

extension SessionCoordinator: SessionGateProviding {}

private extension OfflineTranscriptionCoordinator {
    enum CoordinatorError: Error {
        case descriptorUnavailable
        case invalidProcessorOutput
    }

    func observeSessionGate() async {
        let stream = await sessionGate.snapshotStream()
        for await snapshot in stream {
            handleSessionSnapshot(snapshot)
        }
    }

    func handleSessionSnapshot(_ snapshot: SessionSnapshot) {
        sessionIsIdle = Self.isIdleState(snapshot.sessionState)
        if sessionIsIdle {
            startNextJobIfPossible()
        }
    }

    func startNextJobIfPossible() {
        guard sessionIsIdle else {
            return
        }
        guard processingTask == nil else {
            return
        }
        guard let index = jobs.firstIndex(where: { $0.status == .queued }) else {
            return
        }

        let job = jobs[index]
        jobs[index] = updated(job, status: .inFlight(progress: 0.05))
        activeJobID = job.id
        publishSnapshot()

        processingTask = Task { [weak self] in
            await self?.runJob(id: job.id)
        }
    }

    func runJob(id: UUID) async {
        guard let job = jobs.first(where: { $0.id == id }) else {
            finishProcessingTask(for: id)
            return
        }

        do {
            let descriptor = try await resolveDescriptor(for: job)
            updateInFlightProgress(for: id, progress: 0.12)

            let audio = try await collectAudio(from: job.url, jobID: id)
            try Task.checkCancellation()

            let result = try await transcribe(audio: audio, descriptor: descriptor, job: job)
            try Task.checkCancellation()

            updateInFlightProgress(for: id, progress: 0.92)
            let transcriptID = UUID()
            let entry = TranscriptEntry(
                id: transcriptID,
                timestamp: now(),
                text: result.text,
                audioDuration: Self.seconds(from: result.audioDuration),
                processingDuration: Self.seconds(from: result.processingDuration),
                modeId: nil,
                audioFilename: job.sourceFilename
            )
            try await transcriptRepository.append(entry)
            updateStatus(for: id, status: .completed(transcriptID: transcriptID))
        } catch {
            if Self.isCancellation(error) {
                updateStatus(for: id, status: .cancelled)
            } else {
                let reason = mapFailureReason(from: error)
                if reason == .audioMissing {
                    await nullifyMissingAudioFilename(job.sourceFilename)
                }
                updateStatus(for: id, status: .failed(reason: reason))
            }
        }

        finishProcessingTask(for: id)
    }

    func finishProcessingTask(for id: UUID) {
        if activeJobID == id {
            activeJobID = nil
            processingTask = nil
            startNextJobIfPossible()
        }
    }

    func collectAudio(from url: URL, jobID: UUID) async throws -> PCMBuffer {
        var buffers: [PCMBuffer] = []
        var chunkCount = 0

        for try await buffer in fileSourceAudioStream.stream(from: url) {
            try Task.checkCancellation()
            buffers.append(buffer)
            chunkCount += 1
            let progress = min(0.32, 0.12 + Double(chunkCount) * 0.04)
            updateInFlightProgress(for: jobID, progress: progress)
        }

        return try combinedBuffer(from: buffers)
    }

    func resolveDescriptor(for job: Job) async throws -> ModelDescriptor {
        let descriptor: ModelDescriptor?
        switch job.recipeOverride {
        case .fixedDictation:
            descriptor = await activeASRDescriptor()
        case nil:
            descriptor = await descriptorByID(job.descriptorID)
        }

        guard let descriptor, descriptor.kind == .asr else {
            throw CoordinatorError.descriptorUnavailable
        }
        return descriptor
    }

    func transcribe(
        audio: PCMBuffer,
        descriptor: ModelDescriptor,
        job: Job
    ) async throws -> TranscriptionResult {
        if job.diarize {
            return try await transcribeWithDiarization(audio: audio, descriptor: descriptor, jobID: job.id)
        }
        return try await transcribeWithoutDiarization(audio: audio, descriptor: descriptor, jobID: job.id)
    }

    func transcribeWithoutDiarization(
        audio: PCMBuffer,
        descriptor: ModelDescriptor,
        jobID: UUID
    ) async throws -> TranscriptionResult {
        let transcriber = try processorProvider.transcriber(for: descriptor)

        do {
            updateInFlightProgress(for: jobID, progress: 0.45)
            try await transcriber.prepare()
            updateInFlightProgress(for: jobID, progress: 0.72)
            let rawResult = try await transcriber.transcribe(audio, languageHint: nil)
            updateInFlightProgress(for: jobID, progress: 0.84)
            let processed = try await postProcessedResult(from: rawResult, descriptorID: descriptor.id)
            await transcriber.releaseIdleResources()
            return processed
        } catch {
            await transcriber.releaseIdleResources()
            throw error
        }
    }

    func transcribeWithDiarization(
        audio: PCMBuffer,
        descriptor: ModelDescriptor,
        jobID: UUID
    ) async throws -> TranscriptionResult {
        let transcriber = try processorProvider.transcriber(for: descriptor)
        let diarizer = try processorProvider.diarizer(for: BuiltInModelCatalog.speakerDiarization)
        let processor = DiarizedTurnTranscriptionProcessor(
            diarizer: diarizer,
            transcriber: transcriber,
            sensitivity: diarizationSensitivity
        )

        do {
            updateInFlightProgress(for: jobID, progress: 0.45)
            try await processor.prepare()
            updateInFlightProgress(for: jobID, progress: 0.72)
            let output = try await processor.process(audio: audio, priors: [])
            guard case .text(let rawResult) = output else {
                throw CoordinatorError.invalidProcessorOutput
            }
            updateInFlightProgress(for: jobID, progress: 0.84)
            let processed = try await postProcessedResult(from: rawResult, descriptorID: descriptor.id)
            await diarizer.releaseIdleResources()
            await transcriber.releaseIdleResources()
            return processed
        } catch {
            await diarizer.releaseIdleResources()
            await transcriber.releaseIdleResources()
            throw error
        }
    }

    func postProcessedResult(
        from rawResult: TranscriptionResult,
        descriptorID: String
    ) async throws -> TranscriptionResult {
        let context = PostProcessingContext(
            recordingDuration: rawResult.audioDuration,
            activeMode: nil,
            activeAIModelID: descriptorID,
            systemPrompt: nil,
            segments: rawResult.segments,
            asrConfidence: nil
        )
        let cleanedText = try await postProcessingPipeline.run(rawResult.text, context: context)
        return TranscriptionResult(
            text: cleanedText,
            segments: rawResult.segments,
            audioDuration: rawResult.audioDuration,
            processingDuration: rawResult.processingDuration
        )
    }

    func combinedBuffer(from buffers: [PCMBuffer]) throws -> PCMBuffer {
        guard let first = buffers.first else {
            return try PCMBuffer(samples: [], timestamp: ContinuousClock().now)
        }

        var samples: [Float] = []
        samples.reserveCapacity(buffers.reduce(into: 0) { partialResult, buffer in
            partialResult += buffer.samples.count
        })
        for buffer in buffers {
            samples.append(contentsOf: buffer.samples)
        }

        return try PCMBuffer(
            samples: samples,
            sampleRate: first.sampleRate,
            channelCount: first.channelCount,
            timestamp: first.timestamp
        )
    }

    func resolveSourceURL(from sourceFilename: String) throws -> URL {
        if sourceFilename.hasPrefix("/") {
            return URL(fileURLWithPath: sourceFilename, isDirectory: false).standardizedFileURL
        }

        return try recordingsDirectory()
            .appendingPathComponent(sourceFilename, isDirectory: false)
            .standardizedFileURL
    }

    func persistedAudioFilename(for url: URL) -> String {
        let resolvedURL = url.standardizedFileURL

        guard let recordingsDirectory = try? recordingsDirectory().standardizedFileURL else {
            return resolvedURL.path
        }

        let recordingsPath = recordingsDirectory.path
        let filePath = resolvedURL.path
        let prefix = recordingsPath.hasSuffix("/") ? recordingsPath : recordingsPath + "/"
        if filePath.hasPrefix(prefix) {
            return String(filePath.dropFirst(prefix.count))
        }
        return filePath
    }

    func existingQueuedOrInFlightJobID(forResolvedURL url: URL) -> UUID? {
        let resolvedURL = url.standardizedFileURL
        return jobs.first { job in
            job.url.standardizedFileURL == resolvedURL && job.status.isQueuedOrInFlight
        }?.id
    }

    func enqueueImmediatelyFailedJob(
        url: URL,
        sourceFilename: String,
        descriptorID: String,
        recipeOverride: RecipeOverride?,
        reason: FailureReason
    ) -> UUID {
        let job = Job(
            id: UUID(),
            url: url,
            sourceFilename: sourceFilename,
            descriptorID: descriptorID,
            diarize: false,
            recipeOverride: recipeOverride,
            enqueuedAt: now(),
            status: .failed(reason: reason)
        )
        jobs.append(job)
        publishSnapshot()
        return job.id
    }

    func nullifyMissingAudioFilename(_ sourceFilename: String) async {
        do {
            try await transcriptRepository.nullifyAudioFilenames([sourceFilename])
        } catch {
            logger.error(
                "OfflineTranscriptionCoordinator failed to nullify missing audio filename",
                error: error
            )
        }
    }

    func updateInFlightProgress(for jobID: UUID, progress: Double) {
        guard let index = jobs.firstIndex(where: { $0.id == jobID }) else {
            return
        }
        guard case .inFlight = jobs[index].status else {
            return
        }
        jobs[index] = updated(jobs[index], status: .inFlight(progress: progress))
        publishSnapshot()
    }

    func updateStatus(for jobID: UUID, status: JobStatus) {
        guard let index = jobs.firstIndex(where: { $0.id == jobID }) else {
            return
        }
        jobs[index] = updated(jobs[index], status: status)
        publishSnapshot()
    }

    func updated(_ job: Job, status: JobStatus) -> Job {
        Job(
            id: job.id,
            url: job.url,
            sourceFilename: job.sourceFilename,
            descriptorID: job.descriptorID,
            diarize: job.diarize,
            recipeOverride: job.recipeOverride,
            enqueuedAt: job.enqueuedAt,
            status: status
        )
    }

    func publishSnapshot() {
        let snapshot = jobs
        for continuation in snapshotContinuations.values {
            continuation.yield(snapshot)
        }
    }

    func removeSnapshotContinuation(_ id: UUID) {
        snapshotContinuations[id] = nil
    }

    func placeholderURL(for sourceFilename: String) -> URL {
        if sourceFilename.hasPrefix("/") {
            return URL(fileURLWithPath: sourceFilename, isDirectory: false).standardizedFileURL
        }
        return FileManager.default.temporaryDirectory
            .appendingPathComponent(sourceFilename, isDirectory: false)
            .standardizedFileURL
    }

    func mapFailureReason(from error: Error) -> FailureReason {
        if let error = error as? FileSourceAudioError {
            switch error {
            case .fileMissing:
                return .audioMissing
            case .unsupportedFormat, .conversionFailed:
                return .conversionFailed
            }
        }

        if error is ModelSelectionError || error is CoordinatorError {
            return .modelNotAvailable
        }

        if let error = error as? PersonalScribeError {
            switch error {
            case .modelLoadFailure:
                return .modelNotAvailable
            case .resampleFailure:
                return .conversionFailed
            case .transcriptionFailure:
                return .transcriptionFailed
            case .cancelled:
                return .other("cancelled")
            default:
                return .other(String(describing: error))
            }
        }

        return .other(String(describing: error))
    }

    static func isIdleState(_ state: SessionState) -> Bool {
        switch state {
        case .capturing, .holdRecording, .transcribing:
            false
        case .idle, .completed, .shortExit, .error:
            true
        }
    }

    static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError {
            return true
        }
        if let error = error as? PersonalScribeError, error == .cancelled {
            return true
        }
        return false
    }

    static func seconds(from duration: Duration) -> TimeInterval {
        let components = duration.components
        return TimeInterval(components.seconds)
            + TimeInterval(components.attoseconds) / 1_000_000_000_000_000_000
    }
}

private extension OfflineTranscriptionCoordinator.JobStatus {
    var isQueuedOrInFlight: Bool {
        switch self {
        case .queued, .inFlight:
            true
        case .completed, .failed, .cancelled:
            false
        }
    }
}
