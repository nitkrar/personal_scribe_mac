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
    private let progressBroadcaster = QwenModelDownloadProgressBroadcaster()
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

        let directory = try modelDirectory()
        let variant = try Self.resolveVariant(for: descriptor.id)
        progressBroadcaster.update(Self.loadingSnapshot)

        let manager = self.manager
        let task = Task {
            try await manager.downloadIfNeeded(
                to: directory,
                variant: variant,
                progressHandler: nil
            )
            try await manager.loadModels(from: directory)
        }
        prepareTask = task

        do {
            try await task.value
            hasPreparedModel = true
            prepareTask = nil
            progressBroadcaster.update(Self.finishedSnapshot)
        } catch {
            prepareTask = nil
            progressBroadcaster.update(Self.idleSnapshot)
            throw PersonalScribeError.modelLoadFailure
        }
    }

    public func downloadIfNeeded() async throws {
        let directory = try modelDirectory()
        let variant = try Self.resolveVariant(for: descriptor.id)
        progressBroadcaster.update(Self.downloadingSnapshot)

        let broadcaster = progressBroadcaster
        let progressHandler: DownloadUtils.ProgressHandler = { snapshot in
            broadcaster.update(Self.map(snapshot))
        }

        do {
            try await manager.downloadIfNeeded(
                to: directory,
                variant: variant,
                progressHandler: progressHandler
            )
            progressBroadcaster.update(Self.finishedSnapshot)
        } catch {
            progressBroadcaster.update(Self.idleSnapshot)
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

    static let downloadingSnapshot = ModelDownloadProgress(
        phase: .downloading,
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

    /// Map FluidAudio's download phase to our chip-driving phase.
    /// `.listing` and `.downloading` surface as `.downloading` (chip
    /// shows progress bar). `.compiling` surfaces as `.loading`
    /// (CoreML compile after the network bytes have landed).
    static func map(_ snapshot: DownloadUtils.DownloadProgress) -> ModelDownloadProgress {
        let phase: ModelDownloadProgress.Phase
        switch snapshot.phase {
        case .listing, .downloading:
            phase = .downloading
        case .compiling:
            phase = .loading
        }
        return ModelDownloadProgress(
            phase: phase,
            fractionCompleted: snapshot.fractionCompleted,
            receivedBytes: 0,
            expectedBytes: nil
        )
    }

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
        _ = try await Qwen3AsrModels.download(
            variant: variant,
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

private final class QwenModelDownloadProgressBroadcaster: @unchecked Sendable {
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

        continuations.forEach { $0.yield(snapshot) }
    }
}
