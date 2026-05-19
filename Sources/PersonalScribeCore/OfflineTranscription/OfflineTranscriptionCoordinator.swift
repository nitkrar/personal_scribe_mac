import Foundation

public protocol OfflineTranscriptionRuntimeProviding: Sendable {
    func transcriber(for descriptorID: String) async throws -> any Transcriber
    func diarizer() async throws -> any SpeakerDiarizer
}

public protocol SessionGateProviding: Sendable {
    func isLiveSessionActive() async -> Bool
    func stateStream() async -> AsyncStream<SessionState>
}

public struct InactiveSessionGate: SessionGateProviding, Sendable {
    public init() {}

    public func isLiveSessionActive() async -> Bool {
        false
    }

    public func stateStream() async -> AsyncStream<SessionState> {
        AsyncStream { continuation in
            continuation.yield(.idle)
            continuation.finish()
        }
    }
}

public actor OfflineTranscriptionCoordinator {
    public enum JobStatus: Sendable, Equatable {
        case queued
        case inFlight(progress: Double)
        case completed(transcriptID: UUID)
        case failed(reason: FailureReason)
        case cancelled
    }

    public enum FailureReason: Error, Sendable, Equatable {
        case audioMissing
        case modelNotAvailable
        case conversionFailed
        case transcriptionFailed
        case other(String)
    }

    public enum RecipeOverride: Sendable, Equatable {
        case fixedDictation
    }

    public struct Job: Sendable, Equatable, Identifiable {
        public let id: UUID
        public let url: URL
        public let descriptorID: String
        public let diarize: Bool
        public let recipeOverride: RecipeOverride?
        public let enqueuedAt: Date
        public var status: JobStatus

        public init(
            id: UUID,
            url: URL,
            descriptorID: String,
            diarize: Bool,
            recipeOverride: RecipeOverride?,
            status: JobStatus,
            enqueuedAt: Date = Date()
        ) {
            self.id = id
            self.url = url
            self.descriptorID = descriptorID
            self.diarize = diarize
            self.recipeOverride = recipeOverride
            self.enqueuedAt = enqueuedAt
            self.status = status
        }
    }

    private static let retainedTerminalJobs = 20

    private let runtime: any OfflineTranscriptionRuntimeProviding
    private let defaultBatchDescriptorID: @Sendable () -> String?
    private let fileSource: any FileSourceAudioStreaming
    private let repository: any TranscriptAppending & TranscriptAudioFilenameNullifying
    private let sessionGate: any SessionGateProviding
    private let recordingsDirectory: @Sendable () throws -> URL
    private let now: @Sendable () -> Date
    private let logger: PersonalScribeLogger

    private var jobs: [Job] = []
    private var continuations: [UUID: AsyncStream<[Job]>.Continuation] = [:]
    private var currentJobID: UUID?
    private var currentJobTask: Task<Void, Never>?
    private var gateObservationTask: Task<Void, Never>?

    public init(
        runtime: any OfflineTranscriptionRuntimeProviding,
        defaultBatchDescriptorID: @escaping @Sendable () -> String?,
        fileSource: any FileSourceAudioStreaming,
        repository: any TranscriptAppending & TranscriptAudioFilenameNullifying,
        sessionGate: any SessionGateProviding = InactiveSessionGate(),
        recordingsDirectory: @escaping @Sendable () throws -> URL = { try AppConfig.recordingsDirectory() },
        now: @escaping @Sendable () -> Date = Date.init,
        logger: PersonalScribeLogger
    ) {
        self.runtime = runtime
        self.defaultBatchDescriptorID = defaultBatchDescriptorID
        self.fileSource = fileSource
        self.repository = repository
        self.sessionGate = sessionGate
        self.recordingsDirectory = recordingsDirectory
        self.now = now
        self.logger = logger
        self.gateObservationTask = nil

        Task { [weak self] in
            await self?.installGateObservationTask()
        }
    }

    deinit {
        currentJobTask?.cancel()
        gateObservationTask?.cancel()
    }

    public func enqueueFile(url: URL, descriptorID: String, diarize: Bool) -> UUID {
        let standardizedURL = url.standardizedFileURL
        let jobID = UUID()

        guard !descriptorID.isEmpty else {
            appendTerminalJob(
                Job(
                    id: jobID,
                    url: standardizedURL,
                    descriptorID: descriptorID,
                    diarize: diarize,
                    recipeOverride: nil,
                    status: .failed(reason: .modelNotAvailable),
                    enqueuedAt: now()
                )
            )
            return jobID
        }

        switch storedAudioFilename(for: standardizedURL) {
        case .failure(let error):
            appendTerminalJob(
                Job(
                    id: jobID,
                    url: standardizedURL,
                    descriptorID: descriptorID,
                    diarize: diarize,
                    recipeOverride: nil,
                    status: .failed(reason: .other(Self.describe(error))),
                    enqueuedAt: now()
                )
            )
            return jobID
        case .success(let storedFilename):
            let status: JobStatus = fileExists(at: standardizedURL)
                ? .queued
                : .failed(reason: .audioMissing)
            jobs.append(
                Job(
                    id: jobID,
                    url: standardizedURL,
                    descriptorID: descriptorID,
                    diarize: diarize,
                    recipeOverride: nil,
                    status: status,
                    enqueuedAt: now()
                )
            )
            publishJobs()

            if status == .queued {
                scheduleKickProcessing()
            } else {
                scheduleNullifyAudioFilename(storedFilename)
            }
            return jobID
        }
    }

    public func reTranscribe(sourceFilename: String) -> UUID {
        let descriptorID = defaultBatchDescriptorID() ?? ""
        let jobID = UUID()

        guard !descriptorID.isEmpty else {
            appendTerminalJob(
                Job(
                    id: jobID,
                    url: URL(fileURLWithPath: sourceFilename).standardizedFileURL,
                    descriptorID: descriptorID,
                    diarize: false,
                    recipeOverride: .fixedDictation,
                    status: .failed(reason: .modelNotAvailable),
                    enqueuedAt: now()
                )
            )
            return jobID
        }

        let sourceURL: URL
        do {
            sourceURL = try resolveSourceFilename(sourceFilename)
        } catch {
            appendTerminalJob(
                Job(
                    id: jobID,
                    url: URL(fileURLWithPath: sourceFilename).standardizedFileURL,
                    descriptorID: descriptorID,
                    diarize: false,
                    recipeOverride: .fixedDictation,
                    status: .failed(reason: .other(Self.describe(error))),
                    enqueuedAt: now()
                )
            )
            return jobID
        }

        let status: JobStatus = fileExists(at: sourceURL)
            ? .queued
            : .failed(reason: .audioMissing)
        jobs.append(
            Job(
                id: jobID,
                url: sourceURL,
                descriptorID: descriptorID,
                diarize: false,
                recipeOverride: .fixedDictation,
                status: status,
                enqueuedAt: now()
            )
        )
        publishJobs()

        if status == .queued {
            scheduleKickProcessing()
        } else {
            scheduleNullifyAudioFilename(sourceFilename)
        }
        return jobID
    }

    public func cancelJob(id: UUID) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else {
            return
        }

        switch jobs[index].status {
        case .queued:
            jobs.remove(at: index)
            publishJobs()
            scheduleKickProcessing()
        case .inFlight:
            jobs[index].status = .cancelled
            publishJobs()
            currentJobTask?.cancel()
        case .completed, .failed, .cancelled:
            return
        }
    }

    public func dequeueJob(id: UUID) {
        cancelJob(id: id)
    }

    public func snapshot() -> [Job] {
        jobs
    }

    public func snapshotStream() -> AsyncStream<[Job]> {
        let id = UUID()
        return AsyncStream { continuation in
            continuations[id] = continuation
            continuation.yield(jobs)
            continuation.onTermination = { [weak self] _ in
                Task {
                    await self?.removeContinuation(id: id)
                }
            }
        }
    }
}

private extension OfflineTranscriptionCoordinator {
    func installGateObservationTask() {
        guard gateObservationTask == nil else {
            return
        }

        gateObservationTask = Task { [weak self] in
            await self?.observeGateState()
        }
    }

    func observeGateState() async {
        let stream = await sessionGate.stateStream()
        for await state in stream {
            guard Self.blocksOfflineProcessing(state) == false else {
                continue
            }
            await kickProcessingIfNeeded()
        }
    }

    func scheduleKickProcessing() {
        Task { [weak self] in
            await self?.kickProcessingIfNeeded()
        }
    }

    func scheduleNullifyAudioFilename(_ filename: String) {
        guard !filename.isEmpty else {
            return
        }

        Task { [weak self] in
            await self?.nullifyAudioFilename(filename)
        }
    }

    func kickProcessingIfNeeded() async {
        let liveSessionIsActive = await sessionGate.isLiveSessionActive()
        guard currentJobID == nil else {
            return
        }
        guard liveSessionIsActive == false else {
            return
        }
        guard let index = jobs.firstIndex(where: { $0.status == .queued }) else {
            return
        }

        let job = jobs[index]
        currentJobID = job.id
        jobs[index].status = .inFlight(progress: 0.05)
        publishJobs()

        currentJobTask = Task { [weak self] in
            await self?.executeJob(id: job.id)
        }
    }

    func executeJob(id: UUID) async {
        defer { Task { [weak self] in await self?.finishExecution(for: id) } }

        guard let job = jobs.first(where: { $0.id == id }) else {
            return
        }

        do {
            try Task.checkCancellation()

            let storedFilename = try storedAudioFilename(for: job.url).get()
            guard fileExists(at: job.url) else {
                updateStatus(.failed(reason: .audioMissing), forJobID: job.id)
                try await repository.nullifyAudioFilenames([storedFilename])
                return
            }

            let result = try await transcribe(job: job)
            try Task.checkCancellation()

            let entry = TranscriptEntry(
                id: UUID(),
                timestamp: now(),
                text: result.text,
                audioDuration: Self.seconds(result.audioDuration),
                processingDuration: Self.seconds(result.processingDuration),
                modeId: nil,
                audioFilename: storedFilename
            )

            updateProgress(0.95, forJobID: job.id)
            try await repository.append(entry)
            try Task.checkCancellation()
            updateStatus(.completed(transcriptID: entry.id), forJobID: job.id)
        } catch is CancellationError {
            updateStatus(.cancelled, forJobID: job.id)
        } catch let error as FileSourceAudioError {
            await handleFileSourceError(error, job: job)
        } catch {
            logger.error("OfflineTranscriptionCoordinator job failed", error: error)
            updateStatus(failureReason(for: error).jobStatus, forJobID: job.id)
        }
    }

    func handleFileSourceError(_ error: FileSourceAudioError, job: Job) async {
        switch error {
        case .fileMissing:
            updateStatus(.failed(reason: .audioMissing), forJobID: job.id)
            let storedFilename = (try? storedAudioFilename(for: job.url).get()) ?? job.url.path
            try? await repository.nullifyAudioFilenames([storedFilename])
        case .unsupportedFormat, .conversionFailed:
            updateStatus(.failed(reason: .conversionFailed), forJobID: job.id)
        }
    }

    func transcribe(job: Job) async throws -> TranscriptionResult {
        let audio = try await collectAudio(from: job.url, jobID: job.id)
        updateProgress(0.35, forJobID: job.id)

        if job.diarize {
            return try await diarizedTranscription(audio: audio, descriptorID: job.descriptorID, jobID: job.id)
        }

        let transcriber = try await runtime.transcriber(for: job.descriptorID)
        updateProgress(0.5, forJobID: job.id)
        try await transcriber.prepare()
        updateProgress(0.75, forJobID: job.id)
        return try await transcriber.transcribe(audio, languageHint: nil)
    }

    func collectAudio(
        from url: URL,
        jobID: UUID
    ) async throws -> PCMBuffer {
        let stream = fileSource.stream(from: url)
        var bufferedSamples: [Float] = []
        var sampleRate: Double?
        var channelCount: Int?
        var timestamp: ContinuousClock.Instant?
        var didAdvanceProgress = false

        do {
            for try await buffer in stream {
                try Task.checkCancellation()

                if let sampleRate, buffer.sampleRate != sampleRate {
                    throw FileSourceAudioError.conversionFailed(
                        underlying: PersonalScribeError.resampleFailure
                    )
                }
                if let channelCount, buffer.channelCount != channelCount {
                    throw FileSourceAudioError.conversionFailed(
                        underlying: PersonalScribeError.resampleFailure
                    )
                }

                if sampleRate == nil {
                    sampleRate = buffer.sampleRate
                    channelCount = buffer.channelCount
                    timestamp = buffer.timestamp
                }

                bufferedSamples.append(contentsOf: buffer.samples)
                if !didAdvanceProgress {
                    didAdvanceProgress = true
                    updateProgress(0.15, forJobID: jobID)
                }
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as FileSourceAudioError {
            throw error
        } catch {
            throw FileSourceAudioError.conversionFailed(underlying: error)
        }

        guard
            !bufferedSamples.isEmpty,
            let sampleRate,
            let channelCount,
            let timestamp
        else {
            throw FileSourceAudioError.conversionFailed(
                underlying: PersonalScribeError.resampleFailure
            )
        }

        return try PCMBuffer(
            samples: bufferedSamples,
            sampleRate: sampleRate,
            channelCount: channelCount,
            timestamp: timestamp
        )
    }

    func diarizedTranscription(
        audio: PCMBuffer,
        descriptorID: String,
        jobID: UUID
    ) async throws -> TranscriptionResult {
        let transcriber = try await runtime.transcriber(for: descriptorID)
        let diarizer = try await runtime.diarizer()

        updateProgress(0.45, forJobID: jobID)
        await diarizer.applySensitivity(.balanced)
        async let prepareDiarizer: Void = diarizer.prepare()
        async let prepareTranscriber: Void = transcriber.prepare()
        try await prepareDiarizer
        try await prepareTranscriber

        let turns = try await finalizedTurns(from: diarizer.diarize(audio))
        updateProgress(0.7, forJobID: jobID)
        return try await aggregateTurnTranscriptions(
            turns,
            audio: audio,
            transcriber: transcriber
        )
    }

    func finalizedTurns(
        from stream: AsyncStream<SpeakerDiarizationEvent>
    ) async throws -> [SpeakerTurn] {
        var finalized: [SpeakerTurn] = []

        for await event in stream {
            try Task.checkCancellation()

            switch event {
            case .update(_, let turns):
                for turn in turns where finalized.contains(turn) == false {
                    finalized.append(turn)
                }
            case .terminal(let turns):
                finalized = turns
            case .failed(let reason):
                throw FailureReason.other(reason)
            }
        }

        return finalized.sorted(by: Self.turnsAreOrdered)
    }

    func aggregateTurnTranscriptions(
        _ turns: [SpeakerTurn],
        audio: PCMBuffer,
        transcriber: any Transcriber
    ) async throws -> TranscriptionResult {
        guard !turns.isEmpty else {
            return TranscriptionResult(
                text: "",
                audioDuration: audio.duration,
                processingDuration: .zero
            )
        }

        var lines: [String] = []
        var processingDuration: Duration = .zero
        var labelBySpeakerID: [String: Int] = [:]
        var nextSpeakerLabel = 1

        for turn in turns {
            try Task.checkCancellation()

            let slice = try Self.slice(audio, from: turn.start, to: turn.end)
            guard !slice.samples.isEmpty else {
                continue
            }

            let result = try await transcriber.transcribe(slice, languageHint: nil)
            let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                continue
            }

            let speakerLabel: Int
            if let existing = labelBySpeakerID[turn.speakerID] {
                speakerLabel = existing
            } else {
                speakerLabel = nextSpeakerLabel
                labelBySpeakerID[turn.speakerID] = speakerLabel
                nextSpeakerLabel += 1
            }

            lines.append("Speaker \(speakerLabel): \(text)")
            processingDuration += result.processingDuration
        }

        return TranscriptionResult(
            text: lines.joined(separator: "\n\n"),
            audioDuration: audio.duration,
            processingDuration: processingDuration
        )
    }

    func finishExecution(for id: UUID) async {
        if currentJobID == id {
            currentJobID = nil
            currentJobTask = nil
        }
        await kickProcessingIfNeeded()
    }

    func nullifyAudioFilename(_ filename: String) async {
        do {
            try await repository.nullifyAudioFilenames([filename])
        } catch {
            logger.error(
                "OfflineTranscriptionCoordinator failed to nullify missing audio filename",
                error: error,
                metadata: ["audioFilename": filename]
            )
        }
    }

    func updateProgress(_ progress: Double, forJobID id: UUID) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else {
            return
        }
        guard case .inFlight = jobs[index].status else {
            return
        }
        jobs[index].status = .inFlight(progress: min(max(progress, 0), 1))
        publishJobs()
    }

    func updateStatus(_ status: JobStatus, forJobID id: UUID) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else {
            return
        }
        jobs[index].status = status
        publishJobs()
    }

    func appendTerminalJob(_ job: Job) {
        jobs.append(job)
        publishJobs()
    }

    func publishJobs() {
        trimTerminalHistoryIfNeeded()
        let snapshot = jobs
        for continuation in continuations.values {
            continuation.yield(snapshot)
        }
    }

    func trimTerminalHistoryIfNeeded() {
        let terminalIndices = jobs.indices.filter { jobs[$0].status.isTerminal }
        guard terminalIndices.count > Self.retainedTerminalJobs else {
            return
        }

        let indicesToRemove = Set(terminalIndices.prefix(terminalIndices.count - Self.retainedTerminalJobs))
        jobs = jobs.enumerated().compactMap { offset, job in
            indicesToRemove.contains(offset) ? nil : job
        }
    }

    func removeContinuation(id: UUID) {
        continuations[id] = nil
    }

    func resolveSourceFilename(_ sourceFilename: String) throws -> URL {
        if sourceFilename.hasPrefix("/") {
            return URL(fileURLWithPath: sourceFilename).standardizedFileURL
        }

        return try recordingsDirectory()
            .appendingPathComponent(sourceFilename, isDirectory: false)
            .standardizedFileURL
    }

    func storedAudioFilename(for url: URL) -> Result<String, Error> {
        Result {
            let recordingsRoot = try recordingsDirectory().standardizedFileURL
            let standardizedURL = url.standardizedFileURL
            let recordingsPath = recordingsRoot.path.hasSuffix("/")
                ? recordingsRoot.path
                : recordingsRoot.path + "/"
            if standardizedURL.path.hasPrefix(recordingsPath) {
                return String(standardizedURL.path.dropFirst(recordingsPath.count))
            }
            return standardizedURL.path
        }
    }

    func fileExists(at url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    func failureReason(for error: Error) -> FailureReason {
        switch error {
        case let reason as FailureReason:
            reason
        case let error as FileSourceAudioError:
            switch error {
            case .fileMissing:
                .audioMissing
            case .unsupportedFormat, .conversionFailed:
                .conversionFailed
            }
        case let error as PersonalScribeError:
            switch error {
            case .modelLoadFailure, .invalidActiveMode:
                .modelNotAvailable
            case .resampleFailure:
                .conversionFailed
            case .transcriptionFailure:
                .transcriptionFailed
            case .cancelled:
                .other("cancelled")
            case .micPermissionDenied, .audioEngineFailure, .invalidState:
                .other(Self.describe(error))
            }
        case is ModelSelectionError:
            .modelNotAvailable
        default:
            .other(Self.describe(error))
        }
    }

    static func blocksOfflineProcessing(_ state: SessionState) -> Bool {
        switch state {
        case .capturing, .holdRecording, .transcribing:
            true
        case .idle, .completed, .shortExit, .error:
            false
        }
    }

    static func describe(_ error: Error) -> String {
        let description = String(describing: error)
        return description.isEmpty ? "unknown error" : description
    }

    static func turnsAreOrdered(_ lhs: SpeakerTurn, _ rhs: SpeakerTurn) -> Bool {
        if lhs.start != rhs.start {
            return lhs.start < rhs.start
        }
        if lhs.end != rhs.end {
            return lhs.end < rhs.end
        }
        return lhs.speakerID < rhs.speakerID
    }

    static func slice(
        _ buffer: PCMBuffer,
        from: Duration,
        to: Duration
    ) throws -> PCMBuffer {
        let frameRange = clampedFrameRange(
            from: from,
            to: to,
            sampleRate: buffer.sampleRate,
            frameCount: buffer.frameCount
        )
        let sampleRange = (frameRange.lowerBound * buffer.channelCount)..<(frameRange.upperBound * buffer.channelCount)
        let timestamp = buffer.timestamp.advanced(
            by: duration(forFrameCount: frameRange.lowerBound, sampleRate: buffer.sampleRate)
        )

        return try PCMBuffer(
            samples: Array(buffer.samples[sampleRange]),
            sampleRate: buffer.sampleRate,
            channelCount: buffer.channelCount,
            timestamp: timestamp
        )
    }

    static func clampedFrameRange(
        from: Duration,
        to: Duration,
        sampleRate: Double,
        frameCount: Int
    ) -> Range<Int> {
        let rawStart = Int(floor(seconds(from) * sampleRate))
        let rawEnd = Int(ceil(seconds(to) * sampleRate))
        let lowerBound = min(max(rawStart, 0), frameCount)
        let upperBound = min(max(rawEnd, 0), frameCount)

        guard upperBound > lowerBound else {
            return lowerBound..<lowerBound
        }

        return lowerBound..<upperBound
    }

    static func seconds(_ duration: Duration) -> Double {
        let components = duration.components
        let attosecondsPerSecond = 1_000_000_000_000_000_000.0
        return Double(components.seconds) + (Double(components.attoseconds) / attosecondsPerSecond)
    }

    static func duration(forFrameCount frameCount: Int, sampleRate: Double) -> Duration {
        .seconds(Double(frameCount) / sampleRate)
    }
}

private extension OfflineTranscriptionCoordinator.FailureReason {
    var jobStatus: OfflineTranscriptionCoordinator.JobStatus {
        .failed(reason: self)
    }
}

private extension OfflineTranscriptionCoordinator.JobStatus {
    var isTerminal: Bool {
        switch self {
        case .completed, .failed, .cancelled:
            true
        case .queued, .inFlight:
            false
        }
    }
}
