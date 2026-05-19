import AVFoundation
import FluidAudio
import Foundation
import PersonalScribeCore

public actor FluidAudioStreamingTranscriberAdapter: VadBoundaryStreamingTranscriber {
    public nonisolated let capabilities = TranscriberCapabilities()

    private let descriptor: ModelDescriptor
    private let storageLocator: any StorageLocator
    private let managerResult: Result<any FluidAudioStreamingEouManaging, Error>
    // Kept on the type so the `VadBoundaryStreamingTranscriber` conformance
    // (added by `9d1945b`) compiles, but NOT used. `9d1945b` reverted on
    // 2026-05-19: the FluidAudio streaming manager never emitted partial
    // callbacks while the VAD-gated path was active, so EVERY Parakeet
    // streaming session produced zero EOUs (see
    // `plans/056_streaming_dictation/BUG_parakeet_streaming_diagnostic.md`).
    // Until the underlying FluidAudio streaming decode is debugged or
    // replaced, we use the manager's own `setEouCallback` directly. This
    // re-exposes the known sticky `eouDetected` latch (req-0021) — first
    // utterance pastes, subsequent utterances do not. That is worse than
    // intended but strictly better than zero EOUs ever pasting.
    private let vadBoundarySessionFactory: VadBoundarySessionFactory?
    private let logger: PersonalScribeLogger
    private nonisolated let progressBroadcaster = FluidAudioDownloadProgressBroadcaster()
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

        if let manager = try? resolvedManager() {
            await manager.setPartialCallback { _ in }
            await manager.setEouCallback { _ in }
            await manager.cleanup()
        }

        progressBroadcaster.emit(.idle)
    }

    public nonisolated func transcribe(
        stream: AsyncThrowingStream<PCMBuffer, Error>
    ) -> AsyncThrowingStream<StreamingTranscriptionEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                await self.executeTranscription(
                    from: stream,
                    continuation: continuation
                )
            }

            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }

    // VAD-boundary entry point retained for `VadBoundaryStreamingTranscriber`
    // protocol conformance. `eouSilenceThresholdSeconds` is intentionally
    // ignored here — the VAD-gated EOU path from `9d1945b` was reverted on
    // 2026-05-19 (see header comment on `vadBoundarySessionFactory`). The
    // orchestrator still calls this overload because it does a runtime type
    // check; routing through it (vs the plain `transcribe(stream:)`) is a
    // no-op for now.
    public nonisolated func transcribe(
        stream: AsyncThrowingStream<PCMBuffer, Error>,
        eouSilenceThresholdSeconds: Double
    ) -> AsyncThrowingStream<StreamingTranscriptionEvent, Error> {
        transcribe(stream: stream)
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

private extension FluidAudioStreamingTranscriberAdapter {
    func executeTranscription(
        from stream: AsyncThrowingStream<PCMBuffer, Error>,
        continuation: AsyncThrowingStream<StreamingTranscriptionEvent, Error>.Continuation
    ) async {
        let diagnosticsContext = StreamingDiagnosticsSession.current
            ?? StreamingDiagnosticsSession.Context()

        do {
            try await prepare()
            let manager = try resolvedManager()

            await manager.reset()
            // Direct manager-callback path (restored from pre-`9d1945b`).
            // Manager fires `partialCallback` with cumulative text on every
            // decoded chunk and `eouCallback` once per detected end-of-
            // utterance.
            await manager.setPartialCallback { text in
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                continuation.yield(.partial(text: trimmed))
            }
            await manager.setEouCallback { [logger] text in
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                continuation.yield(.endOfUtterance(text: trimmed))
                // TEMP-DIAG #056-vad-bug: per-EOU emission trace so we
                // can confirm manager callbacks are firing.
                logger.info(
                    "streaming_eou_emitted_direct session=\(diagnosticsContext.sessionID) chars=\(trimmed.count) ms_since_session_start=\(diagnosticsContext.elapsedMilliseconds())"
                )
            }

            var audioDuration: Duration = .zero
            var firstBuffer: PCMBuffer?

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

            // TEMP-DIAG #056-vad-bug: per-session summary so we can see
            // whether the manager produced any EOU events at all. Remove
            // when the streaming Parakeet path is healthy.
            logger.info(
                "streaming_session_summary session=\(diagnosticsContext.sessionID) finalChars=\(finalText.count) ms_since_session_start=\(diagnosticsContext.elapsedMilliseconds())"
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
        await manager.setEouCallback { _ in }
        await manager.reset()
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
