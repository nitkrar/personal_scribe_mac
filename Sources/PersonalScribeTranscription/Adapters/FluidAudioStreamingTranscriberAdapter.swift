import AVFoundation
import FluidAudio
import Foundation
import PersonalScribeCore

typealias FluidAudioStreamingSleep = @Sendable (Duration) async throws -> Void

public actor FluidAudioStreamingTranscriberAdapter: StreamingTranscriber {
    public nonisolated let capabilities = TranscriberCapabilities()

    private let descriptor: ModelDescriptor
    private let storageLocator: any StorageLocator
    private let managerResult: Result<any FluidAudioStreamingEouManaging, Error>
    private let logger: PersonalScribeLogger?
    private let idleUnloadDelay: Duration
    private let sleep: FluidAudioStreamingSleep
    private nonisolated let progressBroadcaster = FluidAudioDownloadProgressBroadcaster()
    private var hasPreparedModel = false
    private var prepareTask: Task<Void, Error>?
    private var idleReleaseTask: Task<Void, Never>?
    private var idleReleaseGeneration: UInt64 = 0

    public init(
        descriptor: ModelDescriptor,
        storageLocator: any StorageLocator = AppConfig.liveStorageLocator()
    ) {
        self.init(
            descriptor: descriptor,
            storageLocator: storageLocator,
            managerResult: Result {
                StreamingEouAsrManager(
                    chunkSize: try StreamingChunkSize(descriptor: descriptor)
                )
            },
            logger: nil,
            idleUnloadDelay: .seconds(30)
        )
    }

    package init(
        descriptor: ModelDescriptor,
        storageLocator: any StorageLocator = AppConfig.liveStorageLocator(),
        logger: PersonalScribeLogger
    ) {
        self.init(
            descriptor: descriptor,
            storageLocator: storageLocator,
            managerResult: Result {
                StreamingEouAsrManager(
                    chunkSize: try StreamingChunkSize(descriptor: descriptor)
                )
            },
            logger: logger,
            idleUnloadDelay: .seconds(30)
        )
    }

    init(
        descriptor: ModelDescriptor,
        storageLocator: any StorageLocator,
        manager: any FluidAudioStreamingEouManaging,
        logger: PersonalScribeLogger? = nil,
        idleUnloadDelay: Duration = .seconds(30),
        sleep: @escaping FluidAudioStreamingSleep = { try await Task.sleep(for: $0) }
    ) {
        self.init(
            descriptor: descriptor,
            storageLocator: storageLocator,
            managerResult: .success(manager),
            logger: logger,
            idleUnloadDelay: idleUnloadDelay,
            sleep: sleep
        )
    }

    private init(
        descriptor: ModelDescriptor,
        storageLocator: any StorageLocator,
        managerResult: Result<any FluidAudioStreamingEouManaging, Error>,
        logger: PersonalScribeLogger?,
        idleUnloadDelay: Duration,
        sleep: @escaping FluidAudioStreamingSleep = { try await Task.sleep(for: $0) }
    ) {
        self.descriptor = descriptor
        self.storageLocator = storageLocator
        self.managerResult = managerResult
        self.logger = logger
        self.idleUnloadDelay = idleUnloadDelay
        self.sleep = sleep
    }

    public func prepare() async throws {
        invalidateIdleRelease()

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
        invalidateIdleRelease()
        await cleanupRuntime()
    }

    public func releaseIdleResources() async {
        guard hasPreparedModel || prepareTask != nil else {
            return
        }

        invalidateIdleRelease()
        let generation = idleReleaseGeneration
        let delay = idleUnloadDelay
        let sleep = sleep
        idleReleaseTask = Task {
            do {
                try await sleep(delay)
            } catch {
                return
            }

            if Task.isCancelled {
                return
            }

            await self.finishIdleRelease(generation: generation)
        }
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
    func cleanup() async
}

private extension FluidAudioStreamingTranscriberAdapter {
    func executeTranscription(
        from stream: AsyncThrowingStream<PCMBuffer, Error>,
        continuation: AsyncThrowingStream<StreamingTranscriptionEvent, Error>.Continuation
    ) async {
        let callbackSummary = StreamingCallbackSummary()
        var bufferCount = 0
        var audioDuration: Duration = .zero
        var outcome = "prepare_failed"
        var finalTextEmpty = true
        defer {
            let callbackSnapshot = callbackSummary.snapshot()
            logger?.info(
                "streaming_adapter_summary — descriptorID=\(descriptor.id) bufferCount=\(bufferCount) partialCount=\(callbackSnapshot.partialCount) eouCount=\(callbackSnapshot.eouCount) outcome=\(outcome) finalTextEmpty=\(finalTextEmpty) audioDurationMs=\(Self.milliseconds(from: audioDuration))"
            )
        }

        do {
            try await prepare()
            let manager = try resolvedManager()
            outcome = "completed"

            await manager.reset()
            await manager.setPartialCallback { text in
                callbackSummary.recordPartial()
                continuation.yield(.partial(text: text))
            }
            await manager.setEouCallback { text in
                callbackSummary.recordEndOfUtterance()
                continuation.yield(.endOfUtterance(text: text))
            }

            var firstBuffer: PCMBuffer?

            do {
                for try await buffer in stream {
                    try Task.checkCancellation()
                    try validateStreamShape(buffer, against: firstBuffer)
                    if firstBuffer == nil {
                        firstBuffer = buffer
                    }
                    bufferCount += 1
                    audioDuration = audioDuration + buffer.duration
                    _ = try await manager.process(
                        audioBuffer: try Self.makeAVAudioPCMBuffer(from: buffer)
                    )
                }
            } catch is CancellationError {
                outcome = "cancelled"
                await reset(manager: manager)
                return
            } catch let error as PersonalScribeError {
                outcome = "stream_failed"
                await reset(manager: manager)
                throw error
            } catch {
                outcome = "stream_failed"
                await reset(manager: manager)
                throw PersonalScribeError.transcriptionFailure
            }

            let finalText: String
            do {
                finalText = try await manager.finish()
            } catch let error as PersonalScribeError {
                outcome = "finish_failed"
                await reset(manager: manager)
                throw error
            } catch {
                outcome = "finish_failed"
                await reset(manager: manager)
                throw PersonalScribeError.transcriptionFailure
            }
            finalTextEmpty = finalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

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
            outcome = "cancelled"
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

    func invalidateIdleRelease() {
        idleReleaseGeneration &+= 1
        idleReleaseTask?.cancel()
        idleReleaseTask = nil
    }

    func finishIdleRelease(generation: UInt64) async {
        guard generation == idleReleaseGeneration else {
            return
        }

        idleReleaseTask = nil
        let hadPrepared = hasPreparedModel
        let hadInFlightPrepare = prepareTask != nil
        guard hadPrepared || hadInFlightPrepare else {
            return
        }

        await cleanupRuntime()
        logger?.info(
            "adapter_idle_release — descriptorID=\(descriptor.id) adapter=\(String(describing: type(of: self))) releasedAfterMs=\(Self.milliseconds(from: idleUnloadDelay)) hadPrepared=\(hadPrepared) hadInFlightPrepare=\(hadInFlightPrepare)"
        )
    }

    func cleanupRuntime() async {
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

    static func milliseconds(from duration: Duration) -> Int {
        let components = duration.components
        let attosecondsPerSecond = 1_000_000_000_000_000_000.0
        let seconds = Double(components.seconds) + (Double(components.attoseconds) / attosecondsPerSecond)
        return Int((seconds * 1000).rounded())
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

private final class StreamingCallbackSummary: @unchecked Sendable {
    struct Snapshot: Sendable {
        let partialCount: Int
        let eouCount: Int
    }

    private let lock = NSLock()
    private var partialCount = 0
    private var eouCount = 0

    func recordPartial() {
        lock.withLock {
            partialCount += 1
        }
    }

    func recordEndOfUtterance() {
        lock.withLock {
            eouCount += 1
        }
    }

    func snapshot() -> Snapshot {
        lock.withLock {
            Snapshot(
                partialCount: partialCount,
                eouCount: eouCount
            )
        }
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
