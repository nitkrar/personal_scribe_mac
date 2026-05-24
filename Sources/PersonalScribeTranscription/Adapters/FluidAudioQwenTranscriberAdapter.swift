import FluidAudio
import Foundation
import PersonalScribeCore

typealias FluidAudioQwenSleep = @Sendable (Duration) async throws -> Void

protocol FluidAudioQwenManaging: Sendable {
    func downloadIfNeeded(
        to directory: URL,
        variant: Qwen3AsrVariant,
        progressHandler: DownloadUtils.ProgressHandler?
    ) async throws
    func loadModels(from directory: URL) async throws
    func transcribe(
        audioSamples: [Float],
        language: Qwen3AsrConfig.Language?
    ) async throws -> String
    func cleanup() async
}

public actor FluidAudioQwenTranscriberAdapter: Transcriber {
    public nonisolated let capabilities = TranscriberCapabilities()

    private let descriptor: ModelDescriptor
    private let storageLocator: any StorageLocator
    private let manager: any FluidAudioQwenManaging
    private let logger: PersonalScribeLogger?
    private let idleUnloadDelay: Duration
    private let sleep: FluidAudioQwenSleep
    private let progressBroadcaster = FluidAudioDownloadProgressBroadcaster()
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
            manager: Self.makeLiveManager(),
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
            manager: Self.makeLiveManager(),
            logger: logger,
            idleUnloadDelay: .seconds(30)
        )
    }

    init(
        descriptor: ModelDescriptor,
        storageLocator: any StorageLocator,
        manager: any FluidAudioQwenManaging,
        logger: PersonalScribeLogger? = nil,
        idleUnloadDelay: Duration = .seconds(30),
        sleep: @escaping FluidAudioQwenSleep = { try await Task.sleep(for: $0) }
    ) {
        self.descriptor = descriptor
        self.storageLocator = storageLocator
        self.manager = manager
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

        let leafDirectory = try modelDirectory()
        try storageLocator.ensureDirectoriesExist()
        let modelsRoot = storageLocator.url(for: .models).standardizedFileURL
        let variant = try Self.resolveVariant(for: descriptor.id)
        progressBroadcaster.emit(.loading)

        let manager = self.manager
        let task = Task {
            try await manager.downloadIfNeeded(
                to: modelsRoot,
                variant: variant,
                progressHandler: nil
            )
            try await manager.loadModels(from: leafDirectory)
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
        try storageLocator.ensureDirectoriesExist()
        let modelsRoot = storageLocator.url(for: .models).standardizedFileURL
        let variant = try Self.resolveVariant(for: descriptor.id)
        progressBroadcaster.emit(.downloading)

        let broadcaster = progressBroadcaster
        let progressHandler: DownloadUtils.ProgressHandler = { snapshot in
            broadcaster.emit(snapshot)
        }

        do {
            try await manager.downloadIfNeeded(
                to: modelsRoot,
                variant: variant,
                progressHandler: progressHandler
            )
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

    public func transcribe(
        _ audio: PCMBuffer,
        languageHint: String?
    ) async throws -> TranscriptionResult {
        try await prepare()

        let clock = ContinuousClock()
        let start = clock.now
        let qwenLanguage = languageHint.flatMap { Qwen3LanguageMap.bcp47ToQwen[$0] }

        do {
            let text = try await manager.transcribe(
                audioSamples: audio.samples,
                language: qwenLanguage
            )
            let processingDuration = start.duration(to: clock.now)

            return TranscriptionResult(
                text: text,
                segments: [],
                audioDuration: audio.duration,
                processingDuration: processingDuration
            )
        } catch {
            throw PersonalScribeError.transcriptionFailure
        }
    }
}

private extension FluidAudioQwenTranscriberAdapter {
    static func makeLiveManager() -> any FluidAudioQwenManaging {
        if #available(macOS 15, *) {
            return LiveFluidAudioQwenManager()
        }

        return UnsupportedFluidAudioQwenManager()
    }

    static func resolveVariant(for id: String) throws -> Qwen3AsrVariant {
        switch id {
        case BuiltInModelCatalog.qwen3AsrF32.id:
            return .f32
        case BuiltInModelCatalog.qwen3AsrInt8.id:
            return .int8
        default:
            throw ModelSelectionError.unknownVoiceModelID(id)
        }
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
        await manager.cleanup()
        progressBroadcaster.emit(.idle)
    }

    func modelDirectory() throws -> URL {
        try storageLocator.ensureDirectoriesExist()

        let directory = storageLocator
            .url(for: .models)
            .appendingPathComponent(descriptor.repoFolderName, isDirectory: true)
            .standardizedFileURL

        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        return directory
    }

    static func milliseconds(from duration: Duration) -> Int {
        let components = duration.components
        let attosecondsPerSecond = 1_000_000_000_000_000_000.0
        let seconds = Double(components.seconds) + (Double(components.attoseconds) / attosecondsPerSecond)
        return Int((seconds * 1000).rounded())
    }
}

@available(macOS 15, *)
private actor LiveFluidAudioQwenManager: FluidAudioQwenManaging {
    private let managerFactory: @Sendable () -> Qwen3AsrManager
    private var manager: Qwen3AsrManager?

    init(
        managerFactory: @escaping @Sendable () -> Qwen3AsrManager = { Qwen3AsrManager() }
    ) {
        self.managerFactory = managerFactory
    }

    func downloadIfNeeded(
        to directory: URL,
        variant: Qwen3AsrVariant,
        progressHandler: DownloadUtils.ProgressHandler?
    ) async throws {
        // Bypass `Qwen3AsrModels.download(variant:to:)` — its `to:`
        // argument is silently ignored (always writes to FluidAudio's
        // own modelsRoot). Calling `DownloadUtils.downloadRepo`
        // directly honors the destination, so files land at
        // `directory.appendingPathComponent(variant.repo.folderName)`
        // — the same path our descriptor's `repoFolderName` resolves to.
        try await DownloadUtils.downloadRepo(
            variant.repo,
            to: directory,
            progressHandler: progressHandler
        )
    }

    func loadModels(from directory: URL) async throws {
        try await resolvedManager().loadModels(from: directory)
    }

    func transcribe(
        audioSamples: [Float],
        language: Qwen3AsrConfig.Language?
    ) async throws -> String {
        try await resolvedManager().transcribe(
            audioSamples: audioSamples,
            language: language
        )
    }

    func cleanup() async {
        manager = nil
    }

    private func resolvedManager() -> Qwen3AsrManager {
        if let manager {
            return manager
        }

        let manager = managerFactory()
        self.manager = manager
        return manager
    }
}

private actor UnsupportedFluidAudioQwenManager: FluidAudioQwenManaging {
    enum UnsupportedOSError: Error {
        case requiresMacOS15
    }

    func downloadIfNeeded(
        to directory: URL,
        variant: Qwen3AsrVariant,
        progressHandler: DownloadUtils.ProgressHandler?
    ) async throws {
        _ = directory
        _ = variant
        _ = progressHandler
        throw UnsupportedOSError.requiresMacOS15
    }

    func loadModels(from directory: URL) async throws {
        _ = directory
        throw UnsupportedOSError.requiresMacOS15
    }

    func transcribe(
        audioSamples: [Float],
        language: Qwen3AsrConfig.Language?
    ) async throws -> String {
        _ = audioSamples
        _ = language
        throw UnsupportedOSError.requiresMacOS15
    }

    func cleanup() async {}
}
