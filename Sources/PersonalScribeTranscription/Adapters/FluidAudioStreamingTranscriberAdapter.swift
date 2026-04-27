import AVFoundation
import FluidAudio
import Foundation
import PersonalScribeCore

public actor FluidAudioStreamingTranscriberAdapter: StreamingTranscriber {
    public nonisolated let capabilities = TranscriberCapabilities()

    private let descriptor: ModelDescriptor
    private let storageLocator: any StorageLocator
    private let managerResult: Result<any FluidAudioStreamingEouManaging, Error>
    private nonisolated let progressBroadcaster = StreamingAdapterProgressBroadcaster()
    private var hasPreparedModel = false
    private var prepareTask: Task<Void, Error>?

    public init(
        descriptor: ModelDescriptor,
        storageLocator: any StorageLocator = AppConfig.liveStorageLocator()
    ) {
        self.descriptor = descriptor
        self.storageLocator = storageLocator
        self.managerResult = Result {
            StreamingEouAsrManager(
                chunkSize: try StreamingChunkSize(descriptor: descriptor)
            )
        }
    }

    init(
        descriptor: ModelDescriptor,
        storageLocator: any StorageLocator,
        manager: any FluidAudioStreamingEouManaging
    ) {
        self.descriptor = descriptor
        self.storageLocator = storageLocator
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
        let parentDirectory = modelDirectory.deletingLastPathComponent()

        let task = Task {
            self.progressBroadcaster.update(Self.loadingSnapshot)
            try await manager.downloadIfNeeded(to: parentDirectory, progressHandler: nil)
            try await manager.loadModels(modelDir: modelDirectory)
        }
        prepareTask = task

        do {
            try await task.value
            hasPreparedModel = true
            prepareTask = nil
            progressBroadcaster.update(Self.finishedSnapshot)
        } catch {
            prepareTask = nil
            progressBroadcaster.update(Self.idleSnapshot)
            throw PersonalScribeError.modelLoadFailure
        }
    }

    public func downloadIfNeeded() async throws {
        let manager = try resolvedManager()
        let parentDirectory = try modelDirectory().deletingLastPathComponent()

        progressBroadcaster.update(Self.downloadingSnapshot)
        let broadcaster = progressBroadcaster
        let progressHandler: DownloadUtils.ProgressHandler = { snapshot in
            broadcaster.update(Self.map(snapshot))
        }
        do {
            try await manager.downloadIfNeeded(to: parentDirectory, progressHandler: progressHandler)
            progressBroadcaster.update(Self.finishedSnapshot)
        } catch {
            progressBroadcaster.update(Self.idleSnapshot)
            throw PersonalScribeError.modelLoadFailure
        }
    }

    public nonisolated func modelDownloadProgress() -> AsyncStream<ModelDownloadProgress> {
        progressBroadcaster.stream()
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
}

private extension FluidAudioStreamingTranscriberAdapter {
    static let idleSnapshot = ModelDownloadProgress(
        phase: .idle,
        fractionCompleted: 0,
        receivedBytes: 0,
        expectedBytes: nil
    )

    static let downloadingSnapshot = ModelDownloadProgress(
        phase: .downloading,
        fractionCompleted: 0,
        receivedBytes: 0,
        expectedBytes: nil
    )

    /// Map FluidAudio's download phase to our chip-driving phase.
    /// `.listing`/`.downloading` → `.downloading` (progress bar);
    /// `.compiling` → `.loading`.
    static func map(_ snapshot: DownloadUtils.DownloadProgress) -> ModelDownloadProgress {
        let phase: ModelDownloadProgress.Phase
        switch snapshot.phase {
        case .listing, .downloading:
            phase = .downloading
        case .compiling:
            phase = .loading
        }
        return ModelDownloadProgress(
            phase: phase,
            fractionCompleted: snapshot.fractionCompleted,
            receivedBytes: 0,
            expectedBytes: nil
        )
    }

    static let loadingSnapshot = ModelDownloadProgress(
        phase: .loading,
        fractionCompleted: 0,
        receivedBytes: 0,
        expectedBytes: nil
    )

    static let finishedSnapshot = ModelDownloadProgress(
        phase: .finished,
        fractionCompleted: 1,
        receivedBytes: 0,
        expectedBytes: nil
    )

    func executeTranscription(
        from stream: AsyncThrowingStream<PCMBuffer, Error>,
        continuation: AsyncThrowingStream<StreamingTranscriptionEvent, Error>.Continuation
    ) async {
        do {
            try await prepare()
            let manager = try resolvedManager()

            await manager.reset()
            await manager.setPartialCallback { text in
                continuation.yield(.partial(text: text))
            }
            await manager.setEouCallback { text in
                continuation.yield(.endOfUtterance(text: text))
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

private final class StreamingAdapterProgressBroadcaster: @unchecked Sendable {
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
            let initialSnapshot = lock.withLock { () -> ModelDownloadProgress in
                continuations[identifier] = continuation
                return snapshot
            }

            continuation.onTermination = { [weak self] _ in
                guard let self else { return }
                _ = self.lock.withLock {
                    self.continuations.removeValue(forKey: identifier)
                }
            }

            continuation.yield(initialSnapshot)
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
