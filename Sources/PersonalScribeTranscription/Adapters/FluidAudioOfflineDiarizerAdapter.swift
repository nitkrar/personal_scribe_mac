import FluidAudio
import Foundation
import PersonalScribeCore

public final class FluidAudioOfflineDiarizerAdapter: @unchecked Sendable, SpeakerDiarizer {
    private static let logger = PersonalScribeLogger(category: PersonalScribeLogCategory.transcription)

    private let descriptor: ModelDescriptor
    private let storageLocator: any StorageLocator
    private let manager: any FluidAudioOfflineDiarizerManaging
    private let progressBroadcaster = FluidAudioDownloadProgressBroadcaster()
    private let lock = NSLock()

    private var hasPreparedModel = false
    private var prepareTask: Task<Void, Error>?
    private var lastAppliedSensitivity: SpeakerSeparationSensitivity?

    public func applySensitivity(_ sensitivity: SpeakerSeparationSensitivity) async {
        let needsReload = lock.withLock { () -> Bool in
            guard lastAppliedSensitivity != sensitivity else {
                return false
            }
            lastAppliedSensitivity = sensitivity
            // Force the next prepare() to rebuild the FluidAudio
            // OfflineDiarizerManager — config is constructor-only on
            // their side, so changing the preset means a fresh manager.
            hasPreparedModel = false
            prepareTask?.cancel()
            prepareTask = nil
            return true
        }
        guard needsReload else { return }
        let config = OfflineDiarizerConfigBuilder.makeConfig(for: sensitivity)
        await manager.applyConfig(config)
    }

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

            progressBroadcaster.emit(.loading)
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
            progressBroadcaster.emit(.finished)
        } catch {
            lock.withLock {
                prepareTask = nil
            }
            progressBroadcaster.emit(.idle)
            throw PersonalScribeError.modelLoadFailure
        }
    }

    public func downloadIfNeeded() async throws {
        guard descriptor.engine == .diarization else {
            throw PersonalScribeError.modelLoadFailure
        }
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

    public func modelDownloadProgress() -> AsyncStream<ModelDownloadProgress> {
        progressBroadcaster.stream()
    }

    public func cleanup() async {
        let inFlightPrepare = lock.withLock { () -> Task<Void, Error>? in
            let task = prepareTask
            prepareTask = nil
            hasPreparedModel = false
            return task
        }
        inFlightPrepare?.cancel()
        await manager.cleanup()
        progressBroadcaster.emit(.idle)
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
                    // Surface the error to the fusion processor as a
                    // `.failed` event rather than swallowing it into a
                    // silent empty transcript. Log first so the
                    // underlying FluidAudio error type / message is
                    // visible in Console.app for diagnosis.
                    Self.logger.error("FluidAudioOfflineDiarizerAdapter.diarize failed", error: error)
                    continuation.yield(.failed(reason: String(describing: error)))
                }

                continuation.finish()
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
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
    func applyConfig(_ config: OfflineDiarizerConfig) async
    func prepareModels(directory: URL?) async throws
    func downloadIfNeeded(
        to directory: URL,
        progressHandler: DownloadUtils.ProgressHandler?
    ) async throws
    func process(audio: [Float]) async throws -> DiarizationResult
    func cleanup() async
}

private final class PrivateFluidAudioOfflineDiarizerManager:
    @unchecked Sendable,
    FluidAudioOfflineDiarizerManaging
{
    private let lock = NSLock()
    private let managerFactory: @Sendable (OfflineDiarizerConfig) -> OfflineDiarizerManager
    private var manager: OfflineDiarizerManager?
    private var currentConfig: OfflineDiarizerConfig

    init(
        managerFactory: @escaping @Sendable (OfflineDiarizerConfig) -> OfflineDiarizerManager
            = { config in OfflineDiarizerManager(config: config) }
    ) {
        self.managerFactory = managerFactory
        self.currentConfig = OfflineDiarizerConfig()
    }

    func applyConfig(_ config: OfflineDiarizerConfig) async {
        lock.withLock {
            currentConfig = config
            // Manager init takes the config — invalidate the cache so
            // the next resolvedManager() builds a fresh one with the
            // updated tuning.
            manager = nil
        }
    }

    func prepareModels(directory: URL?) async throws {
        try await resolvedManager().prepareModels(directory: directory)
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
        try await resolvedManager().process(audio: audio)
    }

    func cleanup() async {
        lock.withLock {
            manager = nil
        }
    }

    private func resolvedManager() -> OfflineDiarizerManager {
        lock.withLock {
            if let manager {
                return manager
            }

            let manager = managerFactory(currentConfig)
            self.manager = manager
            return manager
        }
    }
}
