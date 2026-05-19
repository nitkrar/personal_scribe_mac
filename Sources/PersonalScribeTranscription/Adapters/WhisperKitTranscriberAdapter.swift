@preconcurrency import WhisperKit
import Foundation
import PersonalScribeCore

protocol WhisperKitManaging: WhisperKitArtifactDownloading, Sendable {
    func loadModel(
        modelName: String,
        modelFolder: URL
    ) async throws

    func transcribe(
        audioSamples: [Float],
        languageHint: String?
    ) async throws -> [WhisperKitManagerResult]
    func cleanup() async
}

protocol WhisperKitHubSnapshotting: Sendable {
    func snapshot(
        repoID: String,
        matchingPatterns: [String],
        progressHandler: @escaping @Sendable (Progress) -> Void
    ) async throws -> URL
}

struct WhisperKitManagerResult: Sendable, Equatable {
    let text: String
}

struct WhisperKitRuntimeHandle {
    let transcribeSamples: ([Float], DecodingOptions?) async throws -> [WhisperKitManagerResult]
    let unloadModels: () async -> Void
}

extension HubApiWrapper: WhisperKitHubSnapshotting {
    func snapshot(
        repoID: String,
        matchingPatterns: [String],
        progressHandler: @escaping @Sendable (Progress) -> Void
    ) async throws -> URL {
        try await snapshot(
            from: HubApiWrapper.Repo(id: repoID),
            matching: matchingPatterns,
            progressHandler: progressHandler
        )
    }
}

public actor WhisperKitTranscriberAdapter: Transcriber {
    public nonisolated let capabilities = TranscriberCapabilities()

    private let descriptor: ModelDescriptor
    private let storageLocator: any StorageLocator
    private let manager: any WhisperKitManaging
    private nonisolated let progressBroadcaster = FluidAudioDownloadProgressBroadcaster()
    private let fileManager: FileManager
    private var hasPreparedModel = false
    private var prepareTask: Task<Void, Error>?

    public init(
        descriptor: ModelDescriptor,
        storageLocator: any StorageLocator = AppConfig.liveStorageLocator()
    ) {
        self.init(
            descriptor: descriptor,
            storageLocator: storageLocator,
            manager: LiveWhisperKitManager()
        )
    }

    init(
        descriptor: ModelDescriptor,
        storageLocator: any StorageLocator,
        manager: any WhisperKitManaging,
        fileManager: FileManager = .default
    ) {
        self.descriptor = descriptor
        self.storageLocator = storageLocator
        self.manager = manager
        self.fileManager = fileManager
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
            progressBroadcaster.emit(.idle)
            throw error
        }
    }

    public func downloadIfNeeded() async throws {
        do {
            try await performDownloadIfNeeded(emitFinished: true)
        } catch {
            progressBroadcaster.emit(.idle)
            throw error
        }
    }

    public nonisolated func modelDownloadProgress() -> AsyncStream<ModelDownloadProgress> {
        progressBroadcaster.stream()
    }

    public func cleanup() async {
        let inFlightPrepare = prepareTask
        prepareTask = nil
        hasPreparedModel = false
        inFlightPrepare?.cancel()
        await manager.cleanup()
        progressBroadcaster.emit(.idle)
    }

    public func transcribe(
        _ audio: PCMBuffer,
        languageHint: String?
    ) async throws -> PersonalScribeCore.TranscriptionResult {
        try await prepare()

        let startedAt = ContinuousClock.now

        do {
            let results = try await manager.transcribe(
                audioSamples: audio.samples,
                languageHint: languageHint
            )
            let measuredTotalDuration = startedAt.duration(to: ContinuousClock.now)
            return makeTranscriptionResult(
                from: results,
                audioDuration: audio.duration,
                processingDuration: measuredTotalDuration
            )
        } catch {
            throw PersonalScribeError.transcriptionFailure
        }
    }
}

private extension WhisperKitTranscriberAdapter {
    var artifactStore: WhisperKitArtifactStore {
        WhisperKitArtifactStore(
            descriptor: descriptor,
            storageLocator: storageLocator,
            fileManager: fileManager
        )
    }

    func performPrepare() async throws {
        let modelDirectory = try artifactStore.modelDirectory()
        try await performDownloadIfNeeded(emitFinished: false)
        progressBroadcaster.emit(.loading)

        do {
            try await manager.loadModel(
                modelName: descriptor.repoFolderName,
                modelFolder: modelDirectory
            )
            progressBroadcaster.emit(.finished)
        } catch {
            await manager.cleanup()
            throw PersonalScribeError.modelLoadFailure
        }
    }

    func performDownloadIfNeeded(emitFinished: Bool) async throws {
        try await artifactStore.downloadIfNeeded(
            downloader: manager,
            progressBroadcaster: progressBroadcaster,
            emitFinished: emitFinished
        )
    }

    func makeTranscriptionResult(
        from results: [WhisperKitManagerResult],
        audioDuration: Duration,
        processingDuration: Duration
    ) -> PersonalScribeCore.TranscriptionResult {
        let mergedText = results
            .map(\.text)
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        return PersonalScribeCore.TranscriptionResult(
            text: mergedText,
            audioDuration: audioDuration,
            processingDuration: processingDuration
        )
    }
}

internal actor LiveWhisperKitManager: WhisperKitManaging {
    private let fileManager: FileManager
    private let hubFactory: @Sendable (URL) -> any WhisperKitHubSnapshotting
    private let whisperFactory: (WhisperKitConfig) async throws -> WhisperKitRuntimeHandle
    private var whisperKit: WhisperKitRuntimeHandle?

    init(
        fileManager: FileManager = .default,
        hubFactory: @escaping @Sendable (URL) -> any WhisperKitHubSnapshotting = {
            HubApiWrapper(downloadBase: $0)
        },
        whisperFactory: @escaping (WhisperKitConfig) async throws -> WhisperKitRuntimeHandle = { config in
            let whisperKit = try await WhisperKit(config)
            return WhisperKitRuntimeHandle(
                transcribeSamples: { audioArray, decodeOptions in
                    let results = try await whisperKit.transcribe(
                        audioArray: audioArray,
                        decodeOptions: decodeOptions
                    )
                    return results.map { WhisperKitManagerResult(text: $0.text) }
                },
                unloadModels: {
                    await whisperKit.unloadModels()
                }
            )
        }
    ) {
        self.fileManager = fileManager
        self.hubFactory = hubFactory
        self.whisperFactory = whisperFactory
    }

    func downloadAndStage(
        repoID: String,
        matchingPatterns: [String]?,
        stagingDirectory: URL,
        destination: URL,
        progressHandler: @escaping @Sendable (Progress) -> Void
    ) async throws {
        try fileManager.createDirectory(
            at: stagingDirectory,
            withIntermediateDirectories: true
        )

        let hub = hubFactory(stagingDirectory)
        let snapshotRoot = try await hub.snapshot(
            repoID: repoID,
            matchingPatterns: matchingPatterns ?? [],
            progressHandler: progressHandler
        )
        let snapshotLeaf = resolvedSnapshotLeaf(
            snapshotRoot: snapshotRoot,
            matchingPatterns: matchingPatterns
        )

        try fileManager.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }

        do {
            try fileManager.moveItem(at: snapshotLeaf, to: destination)
        } catch {
            try fileManager.copyItem(at: snapshotLeaf, to: destination)
            try fileManager.removeItem(at: snapshotLeaf)
        }

        try? fileManager.removeItem(at: stagingDirectory)
    }

    func loadModel(
        modelName: String,
        modelFolder: URL
    ) async throws {
        let config = WhisperKitConfig(
            model: modelName,
            modelFolder: modelFolder.path,
            tokenizerFolder: modelFolder.appendingPathComponent("tokenizer", isDirectory: true),
            verbose: false,
            logLevel: .none,
            prewarm: false,
            load: true,
            download: false,
            useBackgroundDownloadSession: false
        )
        whisperKit = try await whisperFactory(config)
    }

    func transcribe(
        audioSamples: [Float],
        languageHint: String?
    ) async throws -> [WhisperKitManagerResult] {
        guard let whisperKit else {
            throw PersonalScribeError.modelLoadFailure
        }

        let decodeOptions = languageHint.map { DecodingOptions(language: $0) }
        return try await whisperKit.transcribeSamples(audioSamples, decodeOptions)
    }

    func cleanup() async {
        if let whisperKit {
            await whisperKit.unloadModels()
        }
        self.whisperKit = nil
    }

    private func resolvedSnapshotLeaf(
        snapshotRoot: URL,
        matchingPatterns: [String]?
    ) -> URL {
        guard
            let matchingPatterns,
            !matchingPatterns.isEmpty
        else {
            return snapshotRoot
        }

        let topLevelComponents = matchingPatterns.compactMap { path -> String? in
            guard path.contains("/") else {
                return nil
            }
            return path.split(separator: "/", maxSplits: 1).first.map(String.init)
        }

        guard
            let component = topLevelComponents.first,
            !component.isEmpty,
            topLevelComponents.allSatisfy({ $0 == component })
        else {
            return snapshotRoot
        }

        return snapshotRoot
            .appendingPathComponent(component, isDirectory: true)
            .standardizedFileURL
    }
}
