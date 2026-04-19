import Foundation
import os.signpost
import SeshatCore

public actor ModelAwareFluidAudioTranscriber: Transcribing {
    private let descriptor: ModelDescriptor
    private let runtimeVariant: FluidAudioRuntimeVariant
    private let storageLocator: any StorageLocator
    private let downloader: any ModelDownloading
    private let inference: any ModelAwareFluidAudioInferencing
    private let logger: SeshatLogger
    private let logSink: (@Sendable (_ level: String, _ message: String) -> Void)?
    private let progressBroadcaster: ModelSelectionDownloadProgressBroadcaster
    private let signposter = OSSignposter(subsystem: SeshatLogger.subsystem, category: "prepare")
    private var hasPreparedModel = false
    private var prepareTask: Task<Void, Error>?

    public init(
        descriptor: ModelDescriptor,
        storageLocator: any StorageLocator = AppConfig.liveStorageLocator(),
        logger: SeshatLogger = SeshatLogger(category: SeshatLogCategory.transcription)
    ) {
        guard let runtimeVariant = try? FluidAudioRuntimeVariant(descriptor: descriptor) else {
            preconditionFailure("Unsupported model descriptor: \(descriptor.id)")
        }

        self.init(
            descriptor: descriptor,
            runtimeVariant: runtimeVariant,
            storageLocator: storageLocator,
            downloader: PrivateModelDownloader(descriptor: descriptor),
            inference: PrivateModelAwareFluidAudioInferenceClient(),
            logger: logger
        )
    }

    init(
        descriptor: ModelDescriptor,
        runtimeVariant: FluidAudioRuntimeVariant,
        storageLocator: any StorageLocator,
        downloader: any ModelDownloading,
        inference: any ModelAwareFluidAudioInferencing,
        logger: SeshatLogger = SeshatLogger(category: SeshatLogCategory.transcription),
        logSink: (@Sendable (_ level: String, _ message: String) -> Void)? = nil
    ) {
        self.descriptor = descriptor
        self.runtimeVariant = runtimeVariant
        self.storageLocator = storageLocator
        self.downloader = downloader
        self.inference = inference
        self.logger = logger
        self.logSink = logSink
        self.progressBroadcaster = ModelSelectionDownloadProgressBroadcaster()
    }

    public func prepare() async throws {
        if hasPreparedModel {
            return
        }

        if let prepareTask {
            return try await prepareTask.value
        }

        let task = Task {
            try await self.performPrepare()
        }
        prepareTask = task

        do {
            try await task.value
            hasPreparedModel = true
            prepareTask = nil
        } catch {
            prepareTask = nil
            progressBroadcaster.update(Self.idleSnapshot)
            throw error
        }
    }

    public func download(
        progress: @escaping @Sendable (ModelDownloadProgress) -> Void
    ) async throws {
        let modelDirectory = try modelDirectory()

        guard !Self.modelArtifactsAreValid(in: modelDirectory, descriptor: descriptor) else {
            return
        }

        do {
            try await ensureValidDownloadedModel(
                at: modelDirectory,
                externalProgress: progress
            )

            let finished = Self.finishedSnapshot(from: progressBroadcaster.currentSnapshot)
            progressBroadcaster.update(finished)
            progress(finished)
        } catch {
            progressBroadcaster.update(Self.idleSnapshot)
            throw error
        }
    }

    public nonisolated func modelDownloadProgress() -> AsyncStream<ModelDownloadProgress> {
        progressBroadcaster.stream()
    }

    public func transcribe(_ audio: PCMBuffer) async throws -> TranscriptionResult {
        try await prepare()

        do {
            let result = try await inference.transcribe(samples: audio.samples)
            return TranscriptionResult(
                text: result.text,
                segments: [],
                audioDuration: audio.duration,
                processingDuration: result.processingDuration
            )
        } catch {
            logError("FluidAudio transcription failed", error: error)
            throw SeshatError.transcriptionFailure
        }
    }

    public func transcribe(
        stream: AsyncThrowingStream<PCMBuffer, Error>
    ) async throws -> TranscriptionResult {
        var bufferedSamples: [Float] = []
        var firstBuffer: PCMBuffer?

        do {
            for try await buffer in stream {
                if let firstBuffer {
                    guard
                        buffer.sampleRate == firstBuffer.sampleRate,
                        buffer.channelCount == firstBuffer.channelCount
                    else {
                        throw ModelSelectionArtifactValidationError.invalidStreamShape
                    }
                } else {
                    firstBuffer = buffer
                }

                bufferedSamples.append(contentsOf: buffer.samples)
            }
        } catch {
            logError("Replay stream transcription failed", error: error)
            throw SeshatError.transcriptionFailure
        }

        do {
            let aggregate = try PCMBuffer(
                samples: bufferedSamples,
                sampleRate: firstBuffer?.sampleRate ?? SeshatConfig.sampleRate,
                channelCount: firstBuffer?.channelCount ?? SeshatConfig.channelCount,
                timestamp: firstBuffer?.timestamp ?? ContinuousClock().now
            )

            return try await transcribe(aggregate)
        } catch let error as SeshatError {
            throw error
        } catch {
            logError("Replay stream transcription failed", error: error)
            throw SeshatError.transcriptionFailure
        }
    }
}

private extension ModelAwareFluidAudioTranscriber {
    static let idleSnapshot = ModelDownloadProgress(
        phase: .idle,
        fractionCompleted: 0,
        receivedBytes: 0,
        expectedBytes: nil
    )

    func performPrepare() async throws {
        let prepareInterval: StaticString = "ModelAwareFluidAudioTranscriber.performPrepare"
        let prepareState = signposter.beginInterval(prepareInterval)
        defer { signposter.endInterval(prepareInterval, prepareState) }

        let modelDirectory = try modelDirectory()

        if !Self.modelArtifactsAreValid(in: modelDirectory, descriptor: descriptor) {
            try await ensureValidDownloadedModel(at: modelDirectory, externalProgress: nil)
        }

        progressBroadcaster.update(
            .init(phase: .loading, fractionCompleted: 1, receivedBytes: 0, expectedBytes: nil)
        )

        do {
            let loadInterval: StaticString = "modelAwareInference.loadModel"
            let loadState = signposter.beginInterval(loadInterval)
            do {
                try await inference.loadModel(
                    from: modelDirectory,
                    runtimeVariant: runtimeVariant
                )
                signposter.endInterval(loadInterval, loadState)
            } catch {
                signposter.endInterval(loadInterval, loadState)
                throw error
            }
        } catch {
            logError("FluidAudio model load failed", error: error)
            throw SeshatError.modelLoadFailure
        }

        progressBroadcaster.update(Self.finishedSnapshot(from: progressBroadcaster.currentSnapshot))
    }

    func modelDirectory() throws -> URL {
        try storageLocator.ensureDirectoriesExist()
        let directory = storageLocator
            .url(for: .models)
            .appendingPathComponent(descriptor.id, isDirectory: true)
            .standardizedFileURL
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    func ensureValidDownloadedModel(
        at modelDirectory: URL,
        externalProgress: (@Sendable (ModelDownloadProgress) -> Void)?
    ) async throws {
        let fileManager = FileManager.default
        let stagingDirectory = FluidAudioTranscriber.stagingDirectory(
            base: modelDirectory.deletingLastPathComponent(),
            descriptor: descriptor
        )

        for attempt in 0..<2 {
            do {
                _ = try await downloader.ensureModelAvailable(
                    at: modelDirectory,
                    progress: { snapshot in
                        let current = progressBroadcaster.currentSnapshot
                        let normalized = Self.normalizedProgress(snapshot, current: current)
                        progressBroadcaster.update(normalized)
                        externalProgress?(normalized)
                    }
                )

                guard Self.modelArtifactsAreValid(in: modelDirectory, descriptor: descriptor) else {
                    throw ModelSelectionArtifactValidationError.invalidArtifacts
                }

                return
            } catch {
                try? fileManager.removeItem(at: stagingDirectory)

                if attempt == 1 {
                    logError("Model download failed", error: error)
                    throw SeshatError.modelDownloadFailure
                }
            }
        }
    }

    func logError(_ message: String, error: Error) {
        logger.error("\(message): \(error.localizedDescription)", error: error)
        logSink?("error", "\(message): \(error.localizedDescription)")
    }

    static func normalizedProgress(
        _ snapshot: ModelDownloadProgress,
        current: ModelDownloadProgress
    ) -> ModelDownloadProgress {
        guard snapshot.phase == .downloading, current.phase == .downloading else {
            return snapshot
        }

        return .init(
            phase: .downloading,
            fractionCompleted: max(snapshot.fractionCompleted, current.fractionCompleted),
            receivedBytes: max(snapshot.receivedBytes, current.receivedBytes),
            expectedBytes: snapshot.expectedBytes ?? current.expectedBytes
        )
    }

    static func finishedSnapshot(from snapshot: ModelDownloadProgress) -> ModelDownloadProgress {
        .init(
            phase: .finished,
            fractionCompleted: 1,
            receivedBytes: snapshot.receivedBytes,
            expectedBytes: snapshot.expectedBytes
        )
    }

    static func modelArtifactsAreValid(in directory: URL, descriptor: ModelDescriptor) -> Bool {
        guard FluidAudioTranscriber.modelsExist(in: directory, descriptor: descriptor) else {
            return false
        }

        let fileManager = FileManager.default

        for path in FluidAudioTranscriber.requiredModelPaths(in: directory, descriptor: descriptor)
        where path.lastPathComponent == "coremldata.bin" {
            guard
                let attributes = try? fileManager.attributesOfItem(atPath: path.path),
                let size = attributes[.size] as? NSNumber,
                size.intValue > 0
            else {
                return false
            }
        }

        let vocabURL = directory.appendingPathComponent("parakeet_vocab.json", isDirectory: false)
        guard
            let data = try? Data(contentsOf: vocabURL),
            !data.isEmpty,
            let first = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .first,
            first == "{" || first == "["
        else {
            return false
        }

        return true
    }
}

private final class ModelSelectionDownloadProgressBroadcaster: @unchecked Sendable {
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

    var currentSnapshot: ModelDownloadProgress {
        lock.withLock { snapshot }
    }
}

private enum ModelSelectionArtifactValidationError: Error {
    case invalidArtifacts
    case invalidStreamShape
}
