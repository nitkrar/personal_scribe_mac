import AVFoundation
import FluidAudio
import Foundation
import PersonalScribeCore

public actor FluidAudioStreamingTranscriberAdapter: VadBoundaryStreamingTranscriber {
    public nonisolated let capabilities = TranscriberCapabilities()

    private let descriptor: ModelDescriptor
    private let storageLocator: any StorageLocator
    private let managerResult: Result<any FluidAudioStreamingEouManaging, Error>
    private let vadBoundarySessionFactory: VadBoundarySessionFactory?
    private let logger: PersonalScribeLogger
    private nonisolated let progressBroadcaster = FluidAudioDownloadProgressBroadcaster()
    private nonisolated let partialInbox = PartialInbox()
    private var hasPreparedModel = false
    private var prepareTask: Task<Void, Error>?

    public init(
        descriptor: ModelDescriptor,
        storageLocator: any StorageLocator = AppConfig.liveStorageLocator(),
        vadBoundarySessionFactory: VadBoundarySessionFactory? = nil,
        logger: PersonalScribeLogger = .testing(category: PersonalScribeLogCategory.transcription)
    ) {
        self.descriptor = descriptor
        self.storageLocator = storageLocator
        self.vadBoundarySessionFactory = vadBoundarySessionFactory
        self.logger = logger
        self.managerResult = Result {
            StreamingEouAsrManager(
                chunkSize: try StreamingChunkSize(descriptor: descriptor)
            )
        }
    }

    init(
        descriptor: ModelDescriptor,
        storageLocator: any StorageLocator,
        manager: any FluidAudioStreamingEouManaging,
        vadBoundarySessionFactory: VadBoundarySessionFactory? = nil,
        logger: PersonalScribeLogger = .testing(category: PersonalScribeLogCategory.transcription)
    ) {
        self.descriptor = descriptor
        self.storageLocator = storageLocator
        self.vadBoundarySessionFactory = vadBoundarySessionFactory
        self.logger = logger
        self.managerResult = .success(manager)
    }

    public func prepare() async throws {
        if hasPreparedModel {
            return
        }

        if let prepareTask {
            return try await prepareTask.value
        }

        let manager = try resolvedManager()
        let modelDirectory = try self.modelDirectory()
        try storageLocator.ensureDirectoriesExist()
        let modelsRoot = storageLocator.url(for: .models).standardizedFileURL

        let task = Task {
            self.progressBroadcaster.emit(.loading)
            try await manager.downloadIfNeeded(to: modelsRoot, progressHandler: nil)
            try await manager.loadModels(modelDir: modelDirectory)
        }
        prepareTask = task

        do {
            try await task.value
            hasPreparedModel = true
            prepareTask = nil
            progressBroadcaster.emit(.finished)
        } catch {
            prepareTask = nil
            progressBroadcaster.emit(.idle)
            throw PersonalScribeError.modelLoadFailure
        }
    }

    public func downloadIfNeeded() async throws {
        let manager = try resolvedManager()
        try storageLocator.ensureDirectoriesExist()
        let modelsRoot = storageLocator.url(for: .models).standardizedFileURL

        progressBroadcaster.emit(.downloading)
        let broadcaster = progressBroadcaster
        let progressHandler: DownloadUtils.ProgressHandler = { snapshot in
            broadcaster.emit(snapshot)
        }
        do {
            try await manager.downloadIfNeeded(to: modelsRoot, progressHandler: progressHandler)
            progressBroadcaster.emit(.finished)
        } catch {
            progressBroadcaster.emit(.idle)
            throw PersonalScribeError.modelLoadFailure
        }
    }

    public nonisolated func modelDownloadProgress() -> AsyncStream<ModelDownloadProgress> {
        progressBroadcaster.stream()
    }

    public func cleanup() async {
        let inFlightPrepare = prepareTask
        prepareTask = nil
        hasPreparedModel = false
        inFlightPrepare?.cancel()
        partialInbox.clear()

        if let manager = try? resolvedManager() {
            await manager.setPartialCallback { _ in }
            await manager.cleanup()
        }

        progressBroadcaster.emit(.idle)
    }

    public nonisolated func transcribe(
        stream: AsyncThrowingStream<PCMBuffer, Error>
    ) -> AsyncThrowingStream<StreamingTranscriptionEvent, Error> {
        transcribe(
            stream: stream,
            eouSilenceThresholdSeconds: Double(
                PreferenceKeys.streamingEouSilenceThresholdMs.default
            ) / 1000
        )
    }

    public nonisolated func transcribe(
        stream: AsyncThrowingStream<PCMBuffer, Error>,
        eouSilenceThresholdSeconds: Double
    ) -> AsyncThrowingStream<StreamingTranscriptionEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                await self.executeTranscription(
                    from: stream,
                    continuation: continuation,
                    eouSilenceThresholdSeconds: eouSilenceThresholdSeconds
                )
            }

            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }
}

extension StreamingEouAsrManager: FluidAudioStreamingEouManaging {
    func downloadIfNeeded(
        to directory: URL,
        progressHandler: DownloadUtils.ProgressHandler?
    ) async throws {
        let repo: Repo
        switch chunkSize {
        case .ms160: repo = .parakeetEou160
        case .ms320: repo = .parakeetEou320
        case .ms1280: repo = .parakeetEou1280
        }
        try await DownloadUtils.downloadRepo(repo, to: directory, progressHandler: progressHandler)
    }
}

protocol FluidAudioStreamingEouManaging: Actor, Sendable {
    func loadModels(modelDir: URL) async throws
    func downloadIfNeeded(
        to directory: URL,
        progressHandler: DownloadUtils.ProgressHandler?
    ) async throws
    func setEouCallback(_ callback: @escaping EouCallback)
    func setPartialCallback(_ callback: @escaping PartialCallback)
    func process(audioBuffer: AVAudioPCMBuffer) async throws -> String
    func finish() async throws -> String
    func reset() async
    func cleanup() async
}

extension FluidAudioStreamingTranscriberAdapter {
    func executeTranscription(
        from stream: AsyncThrowingStream<PCMBuffer, Error>,
        continuation: AsyncThrowingStream<StreamingTranscriptionEvent, Error>.Continuation,
        eouSilenceThresholdSeconds: Double
    ) async {
        do {
            try await prepare()
            let manager = try resolvedManager()
            let diagnosticsContext = StreamingDiagnosticsSession.current
                ?? StreamingDiagnosticsSession.Context()

            await manager.reset()
            await manager.setPartialCallback { text in
                self.partialInbox.append(text)
            }

            var audioDuration: Duration = .zero
            var firstBuffer: PCMBuffer?
            var latestCumulative = ""
            var lastCommittedBoundary = ""
            var emittedUtteranceCount = 0
            let vadSession = await vadBoundarySessionFactory?(eouSilenceThresholdSeconds)
            if vadSession == nil {
                logger.info(
                    "VAD boundary unavailable; falling back to stream-end boundary session=\(diagnosticsContext.sessionID) ms_since_session_start=\(diagnosticsContext.elapsedMilliseconds())"
                )
            }

            do {
                for try await buffer in stream {
                    try Task.checkCancellation()
                    try validateStreamShape(buffer, against: firstBuffer)
                    if firstBuffer == nil {
                        firstBuffer = buffer
                    }
                    audioDuration = audioDuration + buffer.duration
                    _ = try await manager.process(
                        audioBuffer: try Self.makeAVAudioPCMBuffer(from: buffer)
                    )
                    drainPartialsAndEmitRevisions(
                        continuation: continuation,
                        latestCumulative: &latestCumulative,
                        lastCommittedBoundary: lastCommittedBoundary,
                        diagnosticsContext: diagnosticsContext,
                        nextUtterance: emittedUtteranceCount + 1
                    )
                    if let vadEvent = await vadSession?.ingest(buffer.samples),
                       vadEvent == .speechEnded {
                        emitBoundaryIfNeeded(
                            latestCumulative: latestCumulative,
                            lastCommittedBoundary: &lastCommittedBoundary,
                            continuation: continuation,
                            diagnosticsContext: diagnosticsContext,
                            emittedUtteranceCount: &emittedUtteranceCount
                        )
                    }
                }
            } catch is CancellationError {
                await reset(manager: manager)
                return
            } catch let error as PersonalScribeError {
                await reset(manager: manager)
                throw error
            } catch {
                await reset(manager: manager)
                throw PersonalScribeError.transcriptionFailure
            }

            drainPartialsAndEmitRevisions(
                continuation: continuation,
                latestCumulative: &latestCumulative,
                lastCommittedBoundary: lastCommittedBoundary,
                diagnosticsContext: diagnosticsContext,
                nextUtterance: emittedUtteranceCount + 1
            )

            let finalText: String
            do {
                finalText = try await manager.finish()
            } catch let error as PersonalScribeError {
                await reset(manager: manager)
                throw error
            } catch {
                await reset(manager: manager)
                throw PersonalScribeError.transcriptionFailure
            }

            // BUG FIX #056-vad-bug: flush a final boundary at stream end
            // unconditionally, mirroring the WhisperCpp adapter's pattern
            // (see WhisperCppStreamingTranscriberAdapter.swift:298-313).
            // Pre-fix: this only ran when `vadSession == nil` (feature-
            // disabled path). When VAD existed but never returned
            // `.speechEnded` during the session, ZERO EOU events emitted
            // for the whole recording — live card + live cursor both
            // silent. `lastCommittedBoundary` already prevents duplicate
            // emission when VAD did fire at least once.
            let canonicalFinal = finalText.isEmpty ? latestCumulative : finalText
            emitBoundaryIfNeeded(
                latestCumulative: canonicalFinal,
                lastCommittedBoundary: &lastCommittedBoundary,
                continuation: continuation,
                diagnosticsContext: diagnosticsContext,
                emittedUtteranceCount: &emittedUtteranceCount
            )

            // TEMP-DIAG #056-vad-bug: log per-session VAD summary so we
            // can see if a session ended with zero VAD-driven boundaries.
            // Remove once the silent-VAD root cause is identified.
            logger.info(
                "streaming_session_summary session=\(diagnosticsContext.sessionID) vadSessionPresent=\(vadSession != nil) emittedUtteranceCount=\(emittedUtteranceCount) ms_since_session_start=\(diagnosticsContext.elapsedMilliseconds())"
            )

            continuation.yield(
                .finalized(
                    TranscriptionResult(
                        text: finalText,
                        audioDuration: audioDuration,
                        processingDuration: .zero
                    )
                )
            )
            continuation.finish()
            await reset(manager: manager)
        } catch is CancellationError {
            continuation.finish()
        } catch {
            continuation.finish(throwing: error)
        }
    }

    func resolvedManager() throws -> any FluidAudioStreamingEouManaging {
        try managerResult.get()
    }

    func modelDirectory() throws -> URL {
        try storageLocator.ensureDirectoriesExist()
        let directory = storageLocator
            .url(for: .models)
            .appendingPathComponent(descriptor.repoFolderName, isDirectory: true)
            .standardizedFileURL
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    func validateStreamShape(_ buffer: PCMBuffer, against firstBuffer: PCMBuffer?) throws {
        guard let firstBuffer else {
            return
        }

        guard
            buffer.sampleRate == firstBuffer.sampleRate,
            buffer.channelCount == firstBuffer.channelCount
        else {
            throw PersonalScribeError.transcriptionFailure
        }
    }

    func reset(manager: any FluidAudioStreamingEouManaging) async {
        await manager.setPartialCallback { _ in }
        partialInbox.clear()
        await manager.reset()
    }

    func drainPartialsAndEmitRevisions(
        continuation: AsyncThrowingStream<StreamingTranscriptionEvent, Error>.Continuation,
        latestCumulative: inout String,
        lastCommittedBoundary: String,
        diagnosticsContext: StreamingDiagnosticsSession.Context,
        nextUtterance: Int
    ) {
        let inboxItems = partialInbox.drain()
        // TEMP-DIAG #056-vad-bug: log drain shape so we can see if
        // partial callbacks are arriving from the manager and how many
        // queue up between calls. Remove when bug closes.
        if !inboxItems.isEmpty {
            logger.info(
                "adapter_partial_drain session=\(diagnosticsContext.sessionID) inbox=\(inboxItems.count) nextUtterance=\(nextUtterance) ms_since_session_start=\(diagnosticsContext.elapsedMilliseconds())"
            )
        }
        for cumulativeText in inboxItems {
            latestCumulative = cumulativeText
            let derivation = Self.deriveDelta(
                latest: cumulativeText,
                committed: lastCommittedBoundary
            )
            if derivation.usedLongestCommonPrefixFallback {
                logLcpFallback(
                    latest: cumulativeText,
                    committed: lastCommittedBoundary,
                    diagnosticsContext: diagnosticsContext,
                    utterance: nextUtterance
                )
            }
            let trimmed = derivation.delta.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                continuation.yield(.partial(text: trimmed))
            }
        }
    }

    func emitBoundaryIfNeeded(
        latestCumulative: String,
        lastCommittedBoundary: inout String,
        continuation: AsyncThrowingStream<StreamingTranscriptionEvent, Error>.Continuation,
        diagnosticsContext: StreamingDiagnosticsSession.Context,
        emittedUtteranceCount: inout Int
    ) {
        let derivation = Self.deriveDelta(
            latest: latestCumulative,
            committed: lastCommittedBoundary
        )
        if derivation.usedLongestCommonPrefixFallback {
            logLcpFallback(
                latest: latestCumulative,
                committed: lastCommittedBoundary,
                diagnosticsContext: diagnosticsContext,
                utterance: emittedUtteranceCount + 1
            )
        }
        let trimmedDelta = derivation.delta.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedDelta.isEmpty else {
            return
        }
        let emittedText = emittedUtteranceCount == 0
            ? trimmedDelta
            : " " + trimmedDelta

        emittedUtteranceCount += 1
        continuation.yield(.endOfUtterance(text: emittedText))
        lastCommittedBoundary = latestCumulative
        logger.info(
            "streaming_eou_emitted session=\(diagnosticsContext.sessionID) utterance=\(emittedUtteranceCount) ms_since_session_start=\(diagnosticsContext.elapsedMilliseconds()) chars=\(emittedText.count)"
        )
    }

    func logLcpFallback(
        latest: String,
        committed: String,
        diagnosticsContext: StreamingDiagnosticsSession.Context,
        utterance: Int
    ) {
        let lcp = Self.longestCommonPrefix(latest, committed)
        logger.info(
            "streaming_lcp_fallback session=\(diagnosticsContext.sessionID) utterance=\(utterance) ms_since_session_start=\(diagnosticsContext.elapsedMilliseconds()) latest_chars=\(latest.count) committed_chars=\(committed.count) lcp_chars=\(lcp.count)"
        )
    }

    static func makeAVAudioPCMBuffer(from buffer: PCMBuffer) throws -> AVAudioPCMBuffer {
        guard
            let format = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: buffer.sampleRate,
                channels: AVAudioChannelCount(buffer.channelCount),
                interleaved: false
            ),
            let audioBuffer = AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: AVAudioFrameCount(buffer.frameCount)
            ),
            let channelData = audioBuffer.floatChannelData
        else {
            throw PersonalScribeError.resampleFailure
        }

        audioBuffer.frameLength = AVAudioFrameCount(buffer.frameCount)
        for channel in 0..<buffer.channelCount {
            let destination = channelData[channel]
            var frameIndex = 0
            var sampleIndex = channel
            while frameIndex < buffer.frameCount {
                destination[frameIndex] = buffer.samples[sampleIndex]
                frameIndex += 1
                sampleIndex += buffer.channelCount
            }
        }

        return audioBuffer
    }

    struct DeltaDerivation: Sendable, Equatable {
        let delta: String
        let usedLongestCommonPrefixFallback: Bool
    }

    static func deriveDelta(
        latest: String,
        committed: String
    ) -> DeltaDerivation {
        if latest.hasPrefix(committed) {
            return DeltaDerivation(
                delta: String(latest.dropFirst(committed.count)),
                usedLongestCommonPrefixFallback: false
            )
        }

        let lcp = longestCommonPrefix(latest, committed)
        return DeltaDerivation(
            delta: String(latest.dropFirst(lcp.count)),
            usedLongestCommonPrefixFallback: true
        )
    }

    static func longestCommonPrefix(_ lhs: String, _ rhs: String) -> String {
        var lhsIndex = lhs.startIndex
        var rhsIndex = rhs.startIndex

        while lhsIndex < lhs.endIndex,
              rhsIndex < rhs.endIndex,
              lhs[lhsIndex] == rhs[rhsIndex] {
            lhsIndex = lhs.index(after: lhsIndex)
            rhsIndex = rhs.index(after: rhsIndex)
        }

        return String(lhs[..<lhsIndex])
    }
}

private extension StreamingChunkSize {
    init(descriptor: ModelDescriptor) throws {
        switch descriptor.id {
        case BuiltInModelCatalog.parakeetEou160ms.id:
            self = .ms160
        case BuiltInModelCatalog.parakeetEou320ms.id:
            self = .ms320
        case BuiltInModelCatalog.parakeetEou1280ms.id:
            self = .ms1280
        default:
            throw ModelSelectionError.unknownVoiceModelID(descriptor.id)
        }
    }
}

private final class PartialInbox: @unchecked Sendable {
    private let lock = NSLock()
    private var queue: [String] = []

    func append(_ text: String) {
        lock.lock()
        queue.append(text)
        lock.unlock()
    }

    func drain() -> [String] {
        lock.lock()
        let drained = queue
        queue.removeAll(keepingCapacity: true)
        lock.unlock()
        return drained
    }

    func clear() {
        lock.lock()
        queue.removeAll(keepingCapacity: true)
        lock.unlock()
    }
}
