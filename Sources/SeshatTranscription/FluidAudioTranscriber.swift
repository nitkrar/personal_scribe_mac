import Foundation
import SeshatCore

protocol ModelDownloading: Sendable {
    func ensureModelAvailable(
        at directory: URL,
        progress: @escaping @Sendable (ModelDownloadProgress) -> Void
    ) async throws -> URL
}

public actor FluidAudioTranscriber: Transcribing {
    private let downloader: any ModelDownloading
    private let inference: any FluidAudioInferencing
    private let logger: SeshatLogger
    private let logSink: (@Sendable (_ level: String, _ message: String) -> Void)?
    private let progressBroadcaster: DownloadProgressBroadcaster

    public init(
        logger: SeshatLogger = SeshatLogger(category: SeshatLogCategory.transcription)
    ) {
        self.downloader = PrivateModelDownloader()
        self.inference = PrivateFluidAudioInferenceClient()
        self.logger = logger
        self.logSink = nil
        self.progressBroadcaster = DownloadProgressBroadcaster()
    }

    init(
        downloader: any ModelDownloading,
        inference: any FluidAudioInferencing,
        logger: SeshatLogger = SeshatLogger(category: SeshatLogCategory.transcription),
        logSink: (@Sendable (_ level: String, _ message: String) -> Void)? = nil
    ) {
        self.downloader = downloader
        self.inference = inference
        self.logger = logger
        self.logSink = logSink
        self.progressBroadcaster = DownloadProgressBroadcaster()
    }

    static func modelRootDirectory(base: URL) -> URL {
        base.appendingPathComponent(ParakeetArtifact.modelDirectoryName, isDirectory: true)
    }

    static func stagingDirectory(base: URL) -> URL {
        base.appendingPathComponent("\(ParakeetArtifact.modelDirectoryName)-staging", isDirectory: true)
    }

    static func requiredModelPaths(in directory: URL) -> [URL] {
        ParakeetArtifact.requiredRelativePaths.map {
            directory.appendingPathComponent($0, isDirectory: false)
        }
    }

    static func modelsExist(in directory: URL) -> Bool {
        let fileManager = FileManager.default
        return requiredModelPaths(in: directory).allSatisfy { fileManager.fileExists(atPath: $0.path) }
    }

    public func prepare() async throws {
        let modelsDirectory = try SeshatConfig.modelsDirectory()
        let modelDirectory = Self.modelRootDirectory(base: modelsDirectory)

        if !Self.modelArtifactsAreValid(in: modelDirectory) {
            try await ensureValidDownloadedModel(at: modelDirectory)
        }

        do {
            try await inference.loadModel(from: modelDirectory)
        } catch {
            logError("FluidAudio model load failed", error: error)
            throw SeshatError.modelLoadFailure
        }

        progressBroadcaster.update(
            .init(phase: .finished, fractionCompleted: 1, receivedBytes: 0, expectedBytes: nil)
        )
    }

    public nonisolated func modelDownloadProgress() -> AsyncStream<ModelDownloadProgress> {
        progressBroadcaster.stream()
    }

    public func transcribe(_ audio: PCMBuffer) async throws -> TranscriptionResult {
        _ = audio
        fatalError("step 11+")
    }

    public func transcribe(stream: AsyncThrowingStream<PCMBuffer, Error>) async throws -> TranscriptionResult {
        _ = stream
        fatalError("step 12+")
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
                self?.lock.withLock {
                    self?.continuations.removeValue(forKey: identifier)
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
    func ensureValidDownloadedModel(at modelDirectory: URL) async throws {
        let fileManager = FileManager.default

        for attempt in 0..<2 {
            do {
                _ = try await downloader.ensureModelAvailable(
                    at: modelDirectory,
                    progress: { snapshot in
                        Task { await self.recordDownloadProgress(snapshot) }
                    }
                )

                guard Self.modelArtifactsAreValid(in: modelDirectory) else {
                    throw ModelArtifactValidationError.invalidArtifacts
                }

                return
            } catch {
                try? fileManager.removeItem(at: modelDirectory)

                if attempt == 1 {
                    logError("Model download failed", error: error)
                    throw SeshatError.modelDownloadFailure
                }
            }
        }
    }

    func logError(_ message: String, error: Error) {
        logger.error("\(message): \(error.localizedDescription)", error: error)
        logSink?("error", "\(message): \(error.localizedDescription)")
    }

    func recordDownloadProgress(_ snapshot: ModelDownloadProgress) {
        let current = progressBroadcaster.currentSnapshot
        let normalized = normalizedProgress(snapshot, current: current)
        progressBroadcaster.update(normalized)
    }

    func normalizedProgress(
        _ snapshot: ModelDownloadProgress,
        current: ModelDownloadProgress
    ) -> ModelDownloadProgress {
        guard snapshot.phase == .downloading, current.phase == .downloading else {
            return snapshot
        }

        return .init(
            phase: .downloading,
            fractionCompleted: max(snapshot.fractionCompleted, current.fractionCompleted),
            receivedBytes: max(snapshot.receivedBytes, current.receivedBytes),
            expectedBytes: snapshot.expectedBytes ?? current.expectedBytes
        )
    }
}

private extension FluidAudioTranscriber {
    static func modelArtifactsAreValid(in directory: URL) -> Bool {
        guard modelsExist(in: directory) else {
            return false
        }

        let fileManager = FileManager.default

        for path in requiredModelPaths(in: directory) where path.lastPathComponent == "coremldata.bin" {
            guard
                let attributes = try? fileManager.attributesOfItem(atPath: path.path),
                let size = attributes[.size] as? NSNumber,
                size.intValue > 0
            else {
                return false
            }
        }

        let vocabURL = directory.appendingPathComponent("parakeet_vocab.json", isDirectory: false)
        guard
            let data = try? Data(contentsOf: vocabURL),
            !data.isEmpty,
            let contents = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .first,
            contents == "{" || contents == "["
        else {
            return false
        }

        return true
    }
}

private enum ModelArtifactValidationError: Error {
    case invalidArtifacts
}
