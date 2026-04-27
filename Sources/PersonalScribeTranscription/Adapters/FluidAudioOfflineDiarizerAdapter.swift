import FluidAudio
import Foundation
import PersonalScribeCore

public final class FluidAudioOfflineDiarizerAdapter: @unchecked Sendable, SpeakerDiarizer {
    private let descriptor: ModelDescriptor
    private let storageLocator: any StorageLocator
    private let manager: any FluidAudioOfflineDiarizerManaging
    private let progressBroadcaster = OfflineDiarizerDownloadProgressBroadcaster()
    private let lock = NSLock()

    private var hasPreparedModel = false
    private var prepareTask: Task<Void, Error>?

    public convenience init(
        descriptor: ModelDescriptor,
        storageLocator: any StorageLocator = AppConfig.liveStorageLocator()
    ) {
        self.init(
            descriptor: descriptor,
            storageLocator: storageLocator,
            manager: PrivateFluidAudioOfflineDiarizerManager()
        )
    }

    init(
        descriptor: ModelDescriptor,
        storageLocator: any StorageLocator,
        manager: any FluidAudioOfflineDiarizerManaging
    ) {
        self.descriptor = descriptor
        self.storageLocator = storageLocator
        self.manager = manager
    }

    public func prepare() async throws {
        let task = lock.withLock { () -> Task<Void, Error>? in
            if hasPreparedModel {
                return nil
            }

            if let prepareTask {
                return prepareTask
            }

            progressBroadcaster.update(Self.loadingSnapshot)
            let task = Task {
                try await self.performPrepare()
            }
            prepareTask = task
            return task
        }

        guard let task else {
            return
        }

        do {
            try await task.value
            lock.withLock {
                hasPreparedModel = true
                prepareTask = nil
            }
            progressBroadcaster.update(Self.finishedSnapshot)
        } catch {
            lock.withLock {
                prepareTask = nil
            }
            progressBroadcaster.update(Self.idleSnapshot)
            throw PersonalScribeError.modelLoadFailure
        }
    }

    public func downloadIfNeeded() async throws {
        guard descriptor.engine == .diarization else {
            throw PersonalScribeError.modelLoadFailure
        }
        try storageLocator.ensureDirectoriesExist()
        let modelsRoot = storageLocator.url(for: .models).standardizedFileURL

        progressBroadcaster.update(Self.loadingSnapshot)
        do {
            try await manager.downloadIfNeeded(to: modelsRoot, progressHandler: nil)
            progressBroadcaster.update(Self.finishedSnapshot)
        } catch {
            progressBroadcaster.update(Self.idleSnapshot)
            throw PersonalScribeError.modelLoadFailure
        }
    }

    public func modelDownloadProgress() -> AsyncStream<ModelDownloadProgress> {
        progressBroadcaster.stream()
    }

    public func diarize(
        stream: AsyncThrowingStream<PCMBuffer, Error>
    ) -> AsyncStream<SpeakerDiarizationEvent> {
        AsyncStream { continuation in
            let task = Task {
                guard let samples = await Self.collectSamples(from: stream) else {
                    continuation.yield(.terminal([]))
                    continuation.finish()
                    return
                }

                do {
                    try await self.prepare()
                    let result = try await manager.process(audio: samples)
                    continuation.yield(.terminal(Self.turns(from: result)))
                } catch {
                    continuation.yield(.terminal([]))
                }

                continuation.finish()
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
}

extension FluidAudioOfflineDiarizerAdapter {
    static let idleSnapshot = ModelDownloadProgress(
        phase: .idle,
        fractionCompleted: 0,
        receivedBytes: 0,
        expectedBytes: nil
    )

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
}

private extension FluidAudioOfflineDiarizerAdapter {
    func performPrepare() async throws {
        guard descriptor.engine == .diarization else {
            throw PersonalScribeError.modelLoadFailure
        }
        try storageLocator.ensureDirectoriesExist()
        // `OfflineDiarizerManager` expects the models root directory and
        // appends FluidAudio's diarizer repo folder internally.
        let modelsRoot = storageLocator.url(for: .models).standardizedFileURL
        try await manager.downloadIfNeeded(to: modelsRoot, progressHandler: nil)
        try await manager.prepareModels(directory: modelsRoot)
    }

    static func collectSamples(
        from stream: AsyncThrowingStream<PCMBuffer, Error>
    ) async -> [Float]? {
        var bufferedSamples: [Float] = []
        var channelCount: Int?
        var sampleRate: Double?

        do {
            for try await buffer in stream {
                if let channelCount, buffer.channelCount != channelCount {
                    return nil
                }
                if let sampleRate, buffer.sampleRate != sampleRate {
                    return nil
                }
                if channelCount == nil {
                    channelCount = buffer.channelCount
                }
                if sampleRate == nil {
                    sampleRate = buffer.sampleRate
                }
                bufferedSamples.append(contentsOf: buffer.samples)
            }
        } catch {
            return nil
        }

        guard
            !bufferedSamples.isEmpty,
            channelCount == AppConfig.channelCount,
            sampleRate == AppConfig.sampleRate
        else {
            return nil
        }

        return bufferedSamples
    }

    static func turns(from result: DiarizationResult) -> [SpeakerTurn] {
        result.segments.map { segment in
            SpeakerTurn(
                speakerID: segment.speakerId,
                start: .seconds(Double(segment.startTimeSeconds)),
                end: .seconds(Double(segment.endTimeSeconds))
            )
        }
    }
}

protocol FluidAudioOfflineDiarizerManaging: Sendable {
    func prepareModels(directory: URL?) async throws
    func downloadIfNeeded(
        to directory: URL,
        progressHandler: DownloadUtils.ProgressHandler?
    ) async throws
    func process(audio: [Float]) async throws -> DiarizationResult
}

private final class PrivateFluidAudioOfflineDiarizerManager:
    @unchecked Sendable,
    FluidAudioOfflineDiarizerManaging
{
    private let manager: OfflineDiarizerManager

    init(manager: OfflineDiarizerManager = OfflineDiarizerManager()) {
        self.manager = manager
    }

    func prepareModels(directory: URL?) async throws {
        try await manager.prepareModels(directory: directory)
    }

    func downloadIfNeeded(
        to directory: URL,
        progressHandler: DownloadUtils.ProgressHandler?
    ) async throws {
        try await DownloadUtils.downloadRepo(
            .diarizer,
            to: directory,
            variant: "offline",
            progressHandler: progressHandler
        )
    }

    func process(audio: [Float]) async throws -> DiarizationResult {
        try await manager.process(audio: audio)
    }
}

private final class OfflineDiarizerDownloadProgressBroadcaster: @unchecked Sendable {
    private let lock = NSLock()
    private var continuations: [UUID: AsyncStream<ModelDownloadProgress>.Continuation] = [:]
    private var snapshot = FluidAudioOfflineDiarizerAdapter.idleSnapshot

    func stream() -> AsyncStream<ModelDownloadProgress> {
        AsyncStream { continuation in
            let identifier = UUID()
            let initial = lock.withLock { () -> ModelDownloadProgress in
                continuations[identifier] = continuation
                return snapshot
            }

            continuation.onTermination = { [weak self] _ in
                guard let self else {
                    return
                }
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
}
