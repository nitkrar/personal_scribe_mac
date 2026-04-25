import Foundation
import FluidAudio
import os.signpost
import PersonalScribeCore

public actor FluidAudioTranscriber: Transcriber {
    private let inference: any FluidAudioInferencing
    private let logger: PersonalScribeLogger
    private let logSink: (@Sendable (_ level: String, _ message: String) -> Void)?
    private let progressBroadcaster: DownloadProgressBroadcaster
    private let descriptor: ModelDescriptor
    private let signposter = OSSignposter(subsystem: PersonalScribeLogger.subsystem, category: "prepare")
    private var hasPreparedModel = false
    private var prepareTask: Task<Void, Error>?

    public init(
        descriptor: ModelDescriptor = BuiltInModelCatalog.parakeetTDT06Bv2,
        logger: PersonalScribeLogger = PersonalScribeLogger(category: PersonalScribeLogCategory.transcription)
    ) {
        self.inference = PrivateFluidAudioInferenceClient()
        self.logger = logger
        self.logSink = nil
        self.progressBroadcaster = DownloadProgressBroadcaster()
        self.descriptor = descriptor
    }

    init(
        inference: any FluidAudioInferencing,
        logger: PersonalScribeLogger = PersonalScribeLogger(category: PersonalScribeLogCategory.transcription),
        logSink: (@Sendable (_ level: String, _ message: String) -> Void)? = nil,
        descriptor: ModelDescriptor = BuiltInModelCatalog.parakeetTDT06Bv2
    ) {
        self.inference = inference
        self.logger = logger
        self.logSink = logSink
        self.progressBroadcaster = DownloadProgressBroadcaster()
        self.descriptor = descriptor
    }

    public var activeModelId: String {
        descriptor.id
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
        let progressBroadcaster = self.progressBroadcaster

        do {
            let loadInterval: StaticString = "inference.loadModel"
            let loadState = signposter.beginInterval(loadInterval)
            do {
                try await inference.loadModel(
                    from: modelDirectory,
                    runtimeVariant: try FluidAudioRuntimeVariant(descriptor: descriptor),
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

        progressBroadcaster.update(
            .init(phase: .finished, fractionCompleted: 1, receivedBytes: 0, expectedBytes: nil)
        )
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

    func logError(_ message: String, error: Error) {
        logger.error("\(message): \(error.localizedDescription)", error: error)
        logSink?("error", "\(message): \(error.localizedDescription)")
    }
}

private enum ModelArtifactValidationError: Error {
    case invalidStreamShape
}
