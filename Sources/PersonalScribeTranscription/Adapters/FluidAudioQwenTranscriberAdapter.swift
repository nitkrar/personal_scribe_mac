import FluidAudio
import Foundation
import PersonalScribeCore

protocol FluidAudioQwenManaging: Sendable {
    func loadModels(from directory: URL) async throws
    func transcribe(audioSamples: [Float]) async throws -> String
}

public actor FluidAudioQwenTranscriberAdapter: Transcriber2 {
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
        progressBroadcaster.update(Self.loadingSnapshot)

        let manager = self.manager
        let task = Task {
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

    static let finishedSnapshot = ModelDownloadProgress(
        phase: .finished,
        fractionCompleted: 1,
        receivedBytes: 0,
        expectedBytes: nil
    )

    static func makeLiveManager() -> any FluidAudioQwenManaging {
        if #available(macOS 15, *) {
            return LiveFluidAudioQwenManager()
        }

        return UnsupportedFluidAudioQwenManager()
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
