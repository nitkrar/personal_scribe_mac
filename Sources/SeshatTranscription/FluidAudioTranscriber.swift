import Foundation
import os.signpost
import SeshatCore

protocol ModelDownloading: Sendable {
    func ensureModelAvailable(
        at directory: URL,
        progress: @escaping @Sendable (ModelDownloadProgress) -> Void
    ) async throws -> URL
}

public actor FluidAudioTranscriber: Transcribing {
    private let downloader: any ModelDownloading
    private let inference: any FluidAudioInferencing
    private let logger: SeshatLogger
    private let logSink: (@Sendable (_ level: String, _ message: String) -> Void)?
    private let progressBroadcaster: DownloadProgressBroadcaster
    private let descriptor: ModelDescriptor
    private let signposter = OSSignposter(subsystem: SeshatLogger.subsystem, category: "prepare")
    private var hasPreparedModel = false
    private var prepareTask: Task<Void, Error>?

    public init(
        descriptor: ModelDescriptor = ModelRegistry.parakeetTDT06Bv2,
        logger: SeshatLogger = SeshatLogger(category: SeshatLogCategory.transcription)
    ) {
        self.downloader = PrivateModelDownloader(
            descriptor: descriptor,
            storageLocator: AppConfig.liveStorageLocator()
        )
        self.inference = PrivateFluidAudioInferenceClient()
        self.logger = logger
        self.logSink = nil
        self.progressBroadcaster = DownloadProgressBroadcaster()
        self.descriptor = descriptor
    }

    init(
        downloader: any ModelDownloading,
        inference: any FluidAudioInferencing,
        logger: SeshatLogger = SeshatLogger(category: SeshatLogCategory.transcription),
        logSink: (@Sendable (_ level: String, _ message: String) -> Void)? = nil,
        descriptor: ModelDescriptor = ModelRegistry.parakeetTDT06Bv2
    ) {
        self.downloader = downloader
        self.inference = inference
        self.logger = logger
        self.logSink = logSink
        self.progressBroadcaster = DownloadProgressBroadcaster()
        self.descriptor = descriptor
    }

    public var activeModelId: String {
        descriptor.id
    }

    static func stagingDirectory(base: URL, descriptor: ModelDescriptor) -> URL {
        base.appendingPathComponent("\(descriptor.id)-staging", isDirectory: true)
    }

    static func requiredModelPaths(in directory: URL, descriptor: ModelDescriptor) -> [URL] {
        descriptor.requiredRelativePaths.map {
            directory.appendingPathComponent($0, isDirectory: false)
        }
    }

    static func modelsExist(in directory: URL, descriptor: ModelDescriptor) -> Bool {
        let fileManager = FileManager.default
        return requiredModelPaths(in: directory, descriptor: descriptor)
            .allSatisfy { fileManager.fileExists(atPath: $0.path) }
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
            progressBroadcaster.update(
                .init(phase: .idle, fractionCompleted: 0, receivedBytes: 0, expectedBytes: nil)
            )
            throw error
        }
    }

    private func performPrepare() async throws {
        let prepareInterval: StaticString = "FluidAudioTranscriber.performPrepare"
        let prepareState = signposter.beginInterval(prepareInterval)
        defer { signposter.endInterval(prepareInterval, prepareState) }

        let modelDirectory = try modelDirectory()

        if !Self.modelArtifactsAreValid(in: modelDirectory, descriptor: descriptor) {
            try await ensureValidDownloadedModel(at: modelDirectory)
        }

        progressBroadcaster.update(
            .init(phase: .loading, fractionCompleted: 1, receivedBytes: 0, expectedBytes: nil)
        )

        do {
            let loadInterval: StaticString = "inference.loadModel"
            let loadState = signposter.beginInterval(loadInterval)
            do {
                try await inference.loadModel(
                    from: modelDirectory,
                    runtimeVariant: try FluidAudioRuntimeVariant(descriptor: descriptor)
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

        progressBroadcaster.update(
            .init(phase: .finished, fractionCompleted: 1, receivedBytes: 0, expectedBytes: nil)
        )
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

    public func transcribe(stream: AsyncThrowingStream<PCMBuffer, Error>) async throws -> TranscriptionResult {
        var bufferedSamples: [Float] = []
        var firstBuffer: PCMBuffer?

        do {
            for try await buffer in stream {
                if let firstBuffer {
                    guard
                        buffer.sampleRate == firstBuffer.sampleRate,
                        buffer.channelCount == firstBuffer.channelCount
                    else {
                        throw ModelArtifactValidationError.invalidStreamShape
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
                sampleRate: firstBuffer?.sampleRate ?? AppConfig.sampleRate,
                channelCount: firstBuffer?.channelCount ?? AppConfig.channelCount,
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

private final class DownloadProgressBroadcaster: @unchecked Sendable {
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

private extension FluidAudioTranscriber {
    func modelDirectory() throws -> URL {
        try AppConfig.directory(for: descriptor)
    }

    func ensureValidDownloadedModel(at modelDirectory: URL) async throws {
        let fileManager = FileManager.default
        let progressBroadcaster = self.progressBroadcaster
        let stagingDirectory = Self.stagingDirectory(
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
                    }
                )

                guard Self.modelArtifactsAreValid(in: modelDirectory, descriptor: descriptor) else {
                    throw ModelArtifactValidationError.invalidArtifacts
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
}

private extension FluidAudioTranscriber {
    static func modelArtifactsAreValid(in directory: URL, descriptor: ModelDescriptor) -> Bool {
        guard modelsExist(in: directory, descriptor: descriptor) else {
            return false
        }

        let fileManager = FileManager.default

        for path in requiredModelPaths(in: directory, descriptor: descriptor)
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
            let contents = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .first,
            contents == "{" || contents == "["
        else {
            return false
        }

        return true
    }
}

private enum ModelArtifactValidationError: Error {
    case invalidArtifacts
    case invalidStreamShape
}
