import FluidAudio
import Foundation
import os.signpost
import PersonalScribeCore

public actor ModelAwareFluidAudioTranscriber: Transcribing {
    private let descriptor: ModelDescriptor
    private let runtimeVariantResult: Result<FluidAudioRuntimeVariant, ModelSelectionError>
    private let storageLocator: any StorageLocator
    private let inference: any ModelAwareFluidAudioInferencing
    private let logger: PersonalScribeLogger
    private let logSink: (@Sendable (_ level: String, _ message: String) -> Void)?
    private let progressBroadcaster: ModelSelectionDownloadProgressBroadcaster
    private let signposter = OSSignposter(subsystem: PersonalScribeLogger.subsystem, category: "prepare")
    private var hasPreparedModel = false
    private var prepareTask: Task<Void, Error>?

    public init(
        descriptor: ModelDescriptor,
        storageLocator: any StorageLocator = AppConfig.liveStorageLocator(),
        logger: PersonalScribeLogger = PersonalScribeLogger(category: PersonalScribeLogCategory.transcription)
    ) {
        self.init(
            descriptor: descriptor,
            runtimeVariantResult: Self.resolveRuntimeVariant(for: descriptor),
            storageLocator: storageLocator,
            inference: PrivateModelAwareFluidAudioInferenceClient(),
            logger: logger
        )
    }

    init(
        descriptor: ModelDescriptor,
        runtimeVariant: FluidAudioRuntimeVariant,
        storageLocator: any StorageLocator,
        inference: any ModelAwareFluidAudioInferencing,
        logger: PersonalScribeLogger = PersonalScribeLogger(category: PersonalScribeLogCategory.transcription),
        logSink: (@Sendable (_ level: String, _ message: String) -> Void)? = nil
    ) {
        self.init(
            descriptor: descriptor,
            runtimeVariantResult: .success(runtimeVariant),
            storageLocator: storageLocator,
            inference: inference,
            logger: logger,
            logSink: logSink
        )
    }

    private init(
        descriptor: ModelDescriptor,
        runtimeVariantResult: Result<FluidAudioRuntimeVariant, ModelSelectionError>,
        storageLocator: any StorageLocator,
        inference: any ModelAwareFluidAudioInferencing,
        logger: PersonalScribeLogger = PersonalScribeLogger(category: PersonalScribeLogCategory.transcription),
        logSink: (@Sendable (_ level: String, _ message: String) -> Void)? = nil
    ) {
        self.descriptor = descriptor
        self.runtimeVariantResult = runtimeVariantResult
        self.storageLocator = storageLocator
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

        let runtimeVariant = try resolvedRuntimeVariant()

        let task = Task {
            try await self.performPrepare(runtimeVariant: runtimeVariant)
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
        let runtimeVariant = try resolvedRuntimeVariant()
        let modelDirectory = try modelDirectory()
        let progressBroadcaster = self.progressBroadcaster

        do {
            try await inference.loadModel(
                from: modelDirectory,
                runtimeVariant: runtimeVariant,
                progressHandler: { snapshot in
                    let mapped = Self.map(snapshot)
                    progressBroadcaster.update(mapped)
                    progress(mapped)
                }
            )

            let finished = Self.finishedSnapshot(from: progressBroadcaster.currentSnapshot)
            progressBroadcaster.update(finished)
            progress(finished)
        } catch {
            progressBroadcaster.update(Self.idleSnapshot)
            logError("FluidAudio model load failed", error: error)
            throw PersonalScribeError.modelLoadFailure
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
            throw PersonalScribeError.transcriptionFailure
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
            throw PersonalScribeError.transcriptionFailure
        }

        do {
            let aggregate = try PCMBuffer(
                samples: bufferedSamples,
                sampleRate: firstBuffer?.sampleRate ?? AppConfig.sampleRate,
                channelCount: firstBuffer?.channelCount ?? AppConfig.channelCount,
                timestamp: firstBuffer?.timestamp ?? ContinuousClock().now
            )

            return try await transcribe(aggregate)
        } catch let error as PersonalScribeError {
            throw error
        } catch {
            logError("Replay stream transcription failed", error: error)
            throw PersonalScribeError.transcriptionFailure
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

    static func resolveRuntimeVariant(
        for descriptor: ModelDescriptor
    ) -> Result<FluidAudioRuntimeVariant, ModelSelectionError> {
        do {
            return .success(try FluidAudioRuntimeVariant(descriptor: descriptor))
        } catch {
            return .failure(.descriptorNotRegistered(id: descriptor.id))
        }
    }

    func resolvedRuntimeVariant() throws -> FluidAudioRuntimeVariant {
        try runtimeVariantResult.get()
    }

    func performPrepare(runtimeVariant: FluidAudioRuntimeVariant) async throws {
        let prepareInterval: StaticString = "ModelAwareFluidAudioTranscriber.performPrepare"
        let prepareState = signposter.beginInterval(prepareInterval)
        defer { signposter.endInterval(prepareInterval, prepareState) }

        let modelDirectory = try modelDirectory()
        let progressBroadcaster = self.progressBroadcaster

        do {
            let loadInterval: StaticString = "modelAwareInference.loadModel"
            let loadState = signposter.beginInterval(loadInterval)
            do {
                try await inference.loadModel(
                    from: modelDirectory,
                    runtimeVariant: runtimeVariant,
                    progressHandler: { snapshot in
                        progressBroadcaster.update(Self.map(snapshot))
                    }
                )
                signposter.endInterval(loadInterval, loadState)
            } catch {
                signposter.endInterval(loadInterval, loadState)
                throw error
            }
        } catch {
            logError("FluidAudio model load failed", error: error)
            throw PersonalScribeError.modelLoadFailure
        }

        progressBroadcaster.update(Self.finishedSnapshot(from: progressBroadcaster.currentSnapshot))
    }

    static func map(_ snapshot: DownloadUtils.DownloadProgress) -> ModelDownloadProgress {
        switch snapshot.phase {
        case .listing, .downloading:
            return .init(
                phase: .downloading,
                fractionCompleted: snapshot.fractionCompleted,
                receivedBytes: 0,
                expectedBytes: nil
            )
        case .compiling:
            return .init(
                phase: .loading,
                fractionCompleted: snapshot.fractionCompleted,
                receivedBytes: 0,
                expectedBytes: nil
            )
        }
    }

    func modelDirectory() throws -> URL {
        // #024.5: derive the on-disk folder from FluidAudio's source of
        // truth (`Repo.folderName`) via `descriptor.repoFolderName`.
        // Aligns our cache layout with what `AsrModels.load(from:)`
        // expects, removing silent re-download risk on FluidAudio
        // upstream folder renames.
        try storageLocator.ensureDirectoriesExist()
        let directory = storageLocator
            .url(for: .models)
            .appendingPathComponent(descriptor.repoFolderName, isDirectory: true)
            .standardizedFileURL
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    func logError(_ message: String, error: Error) {
        logger.error("\(message): \(error.localizedDescription)", error: error)
        logSink?("error", "\(message): \(error.localizedDescription)")
    }

    static func finishedSnapshot(from snapshot: ModelDownloadProgress) -> ModelDownloadProgress {
        .init(
            phase: .finished,
            fractionCompleted: 1,
            receivedBytes: snapshot.receivedBytes,
            expectedBytes: snapshot.expectedBytes
        )
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
    case invalidStreamShape
}
