import FluidAudio
import Foundation
import PersonalScribeCore

protocol FluidAudioQwenManaging: Sendable {
    func downloadIfNeeded(
        to directory: URL,
        variant: Qwen3AsrVariant,
        progressHandler: DownloadUtils.ProgressHandler?
    ) async throws
    func loadModels(from directory: URL) async throws
    func transcribe(audioSamples: [Float]) async throws -> String
}

public actor FluidAudioQwenTranscriberAdapter: Transcriber {
    public nonisolated let capabilities = TranscriberCapabilities()

    private let descriptor: ModelDescriptor
    private let storageLocator: any StorageLocator
    private let manager: any FluidAudioQwenManaging
    private let progressBroadcaster = FluidAudioDownloadProgressBroadcaster()
    private var hasPreparedModel = false
    private var prepareTask: Task<Void, Error>?

    public init(
        descriptor: ModelDescriptor,
        storageLocator: any StorageLocator = AppConfig.liveStorageLocator()
    ) {
        self.init(
            descriptor: descriptor,
            storageLocator: storageLocator,
            manager: Self.makeLiveManager()
        )
    }

    init(
        descriptor: ModelDescriptor,
        storageLocator: any StorageLocator,
        manager: any FluidAudioQwenManaging
    ) {
        self.descriptor = descriptor
        self.storageLocator = storageLocator
        self.manager = manager
    }

    public func prepare() async throws {
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

    public func transcribe(_ audio: PCMBuffer) async throws -> TranscriptionResult {
        try await prepare()

        let clock = ContinuousClock()
        let start = clock.now

        do {
            let text = try await manager.transcribe(audioSamples: audio.samples)
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
}

@available(macOS 15, *)
private actor LiveFluidAudioQwenManager: FluidAudioQwenManaging {
    private let manager = Qwen3AsrManager()

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
        try await manager.loadModels(from: directory)
    }

    func transcribe(audioSamples: [Float]) async throws -> String {
        try await manager.transcribe(audioSamples: audioSamples)
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

    func transcribe(audioSamples: [Float]) async throws -> String {
        _ = audioSamples
        throw UnsupportedOSError.requiresMacOS15
    }
}

