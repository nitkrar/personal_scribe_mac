@preconcurrency import WhisperKit
import Foundation
import PersonalScribeCore

protocol WhisperKitManaging: Sendable {
    func downloadAndStage(
        repoID: String,
        relativePaths: [String]?,
        stagingDirectory: URL,
        destination: URL,
        progressHandler: @escaping @Sendable (Progress) -> Void
    ) async throws

    func loadModel(
        modelName: String,
        modelFolder: URL
    ) async throws

    func transcribe(audioSamples: [Float]) async throws -> [WhisperKitManagerResult]
    func cleanup() async
}

protocol WhisperKitHubSnapshotting: Sendable {
    func snapshot(
        repoID: String,
        relativePaths: [String],
        progressHandler: @escaping @Sendable (Progress) -> Void
    ) async throws -> URL
}

struct WhisperKitManagerResult: Sendable, Equatable {
    let text: String
}

extension HubApiWrapper: WhisperKitHubSnapshotting {
    func snapshot(
        repoID: String,
        relativePaths: [String],
        progressHandler: @escaping @Sendable (Progress) -> Void
    ) async throws -> URL {
        try await snapshot(
            from: HubApiWrapper.Repo(id: repoID),
            matching: relativePaths,
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

    public func transcribe(_ audio: PCMBuffer) async throws -> PersonalScribeCore.TranscriptionResult {
        try await prepare()

        let startedAt = ContinuousClock.now

        do {
            let results = try await manager.transcribe(audioSamples: audio.samples)
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
    struct DownloadPlan: Sendable {
        let bundleRelativePaths: [String]
        let tokenizerRelativePaths: [String]
        let bundleFractionRange: ClosedRange<Double>
        let tokenizerFractionRange: ClosedRange<Double>
    }

    func performPrepare() async throws {
        let modelDirectory = try modelDirectory()
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
        try storageLocator.ensureDirectoriesExist()
        let modelDirectory = try modelDirectory()

        guard
            !WhisperKitArtifactFilesystem.modelArtifactsAreValid(
                in: modelDirectory,
                descriptor: descriptor,
                fileManager: fileManager
            )
        else {
            if emitFinished {
                progressBroadcaster.emit(.finished)
            }
            return
        }

        guard let tokenizerSource = descriptor.tokenizerSource, !tokenizerSource.isEmpty else {
            throw PersonalScribeError.modelLoadFailure
        }

        let plan = try downloadPlan()
        let stagingDirectory = stagingDirectory()
        let tokenizerDirectory = modelDirectory
            .appendingPathComponent("tokenizer", isDirectory: true)
            .standardizedFileURL
        let broadcaster = progressBroadcaster

        do {
            try cleanupPartialDownload(
                modelDirectory: modelDirectory,
                stagingDirectory: stagingDirectory
            )
            progressBroadcaster.emit(.downloading)

            try await manager.downloadAndStage(
                repoID: descriptor.repository,
                relativePaths: plan.bundleRelativePaths,
                stagingDirectory: stagingDirectory,
                destination: modelDirectory,
                progressHandler: { progress in
                    Self.emitDownloadProgress(
                        progress,
                        fractionRange: plan.bundleFractionRange,
                        broadcaster: broadcaster
                    )
                }
            )

            try await manager.downloadAndStage(
                repoID: tokenizerSource,
                relativePaths: plan.tokenizerRelativePaths,
                stagingDirectory: stagingDirectory,
                destination: tokenizerDirectory,
                progressHandler: { progress in
                    Self.emitDownloadProgress(
                        progress,
                        fractionRange: plan.tokenizerFractionRange,
                        broadcaster: broadcaster
                    )
                }
            )
        } catch {
            try? cleanupPartialDownload(
                modelDirectory: modelDirectory,
                stagingDirectory: stagingDirectory
            )
            throw PersonalScribeError.modelLoadFailure
        }

        if emitFinished {
            progressBroadcaster.emit(.finished)
        }
    }

    static func emitDownloadProgress(
        _ progress: Progress,
        fractionRange: ClosedRange<Double>,
        broadcaster: FluidAudioDownloadProgressBroadcaster
    ) {
        let boundedFraction = min(max(progress.fractionCompleted, 0), 1)
        let scaledFraction = fractionRange.lowerBound
            + ((fractionRange.upperBound - fractionRange.lowerBound) * boundedFraction)
        let expectedBytes = progress.totalUnitCount > 0 ? Int64(progress.totalUnitCount) : nil

        broadcaster.emit(ModelDownloadProgress(
            phase: .downloading,
            fractionCompleted: scaledFraction,
            receivedBytes: Int64(max(progress.completedUnitCount, 0)),
            expectedBytes: expectedBytes
        ))
    }

    func modelDirectory() throws -> URL {
        try storageLocator.ensureDirectoriesExist()
        let directory = storageLocator
            .url(for: .models)
            .appendingPathComponent(descriptor.repoFolderName, isDirectory: true)
            .standardizedFileURL
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory
    }

    func stagingDirectory() -> URL {
        storageLocator
            .url(for: .models)
            .appendingPathComponent(".staging", isDirectory: true)
            .appendingPathComponent(descriptor.id, isDirectory: true)
            .standardizedFileURL
    }

    func downloadPlan() throws -> DownloadPlan {
        let bundleRelativePaths = descriptor.requiredRelativePaths
            .filter { !$0.hasPrefix("tokenizer/") }
            .map { "\(descriptor.repoFolderName)/\($0)" }
        let tokenizerRelativePaths = descriptor.requiredRelativePaths
            .filter { $0.hasPrefix("tokenizer/") }
            .map { String($0.dropFirst("tokenizer/".count)) }

        guard !bundleRelativePaths.isEmpty, !tokenizerRelativePaths.isEmpty else {
            throw PersonalScribeError.modelLoadFailure
        }

        // Tokenizer support files are only a few MB versus the
        // CoreML bundle's hundreds of MB, so reserve the final 5% of
        // the synthetic fraction range for the tokenizer phase.
        return DownloadPlan(
            bundleRelativePaths: bundleRelativePaths,
            tokenizerRelativePaths: tokenizerRelativePaths,
            bundleFractionRange: 0...0.95,
            tokenizerFractionRange: 0.95...1
        )
    }

    func cleanupPartialDownload(
        modelDirectory: URL,
        stagingDirectory: URL
    ) throws {
        if fileManager.fileExists(atPath: modelDirectory.path) {
            try fileManager.removeItem(at: modelDirectory)
        }

        if fileManager.fileExists(atPath: stagingDirectory.path) {
            try fileManager.removeItem(at: stagingDirectory)
        }
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

private enum WhisperKitArtifactFilesystem {
    static func modelArtifactsAreValid(
        in directory: URL,
        descriptor: ModelDescriptor,
        fileManager: FileManager
    ) -> Bool {
        let requiredPaths = descriptor.requiredRelativePaths.map {
            directory.appendingPathComponent($0, isDirectory: false)
        }

        guard requiredPaths.allSatisfy({ fileManager.fileExists(atPath: $0.path) }) else {
            return false
        }

        for path in requiredPaths where path.lastPathComponent == "coremldata.bin" {
            guard
                let attributes = try? fileManager.attributesOfItem(atPath: path.path),
                let size = attributes[.size] as? NSNumber,
                size.intValue > 0
            else {
                return false
            }
        }

        for path in requiredPaths where path.pathExtension == "json" {
            guard
                let data = try? Data(contentsOf: path),
                !data.isEmpty,
                let first = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .first,
                first == "{" || first == "["
            else {
                return false
            }
        }

        return true
    }
}

internal actor LiveWhisperKitManager: WhisperKitManaging {
    private let fileManager: FileManager
    private let hubFactory: @Sendable (URL) -> any WhisperKitHubSnapshotting
    private let whisperFactory: (WhisperKitConfig) async throws -> WhisperKit
    private var whisperKit: WhisperKit?

    init(
        fileManager: FileManager = .default,
        hubFactory: @escaping @Sendable (URL) -> any WhisperKitHubSnapshotting = {
            HubApiWrapper(downloadBase: $0)
        },
        whisperFactory: @escaping (WhisperKitConfig) async throws -> WhisperKit = { config in
            try await WhisperKit(config)
        }
    ) {
        self.fileManager = fileManager
        self.hubFactory = hubFactory
        self.whisperFactory = whisperFactory
    }

    func downloadAndStage(
        repoID: String,
        relativePaths: [String]?,
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
            relativePaths: relativePaths ?? [],
            progressHandler: progressHandler
        )
        let snapshotLeaf = resolvedSnapshotLeaf(
            snapshotRoot: snapshotRoot,
            relativePaths: relativePaths
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

    func transcribe(audioSamples: [Float]) async throws -> [WhisperKitManagerResult] {
        guard let whisperKit else {
            throw PersonalScribeError.modelLoadFailure
        }

        let results = try await whisperKit.transcribe(audioArray: audioSamples)
        return results.map { WhisperKitManagerResult(text: $0.text) }
    }

    func cleanup() async {
        if let whisperKit {
            await whisperKit.unloadModels()
        }
        self.whisperKit = nil
    }

    private func resolvedSnapshotLeaf(
        snapshotRoot: URL,
        relativePaths: [String]?
    ) -> URL {
        guard
            let relativePaths,
            !relativePaths.isEmpty
        else {
            return snapshotRoot
        }

        let topLevelComponents = relativePaths.compactMap { path -> String? in
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
