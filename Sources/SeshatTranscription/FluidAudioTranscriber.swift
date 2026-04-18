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

    public init(
        logger: SeshatLogger = SeshatLogger(category: SeshatLogCategory.transcription)
    ) {
        self.downloader = PrivateModelDownloader()
        self.inference = PrivateFluidAudioInferenceClient()
        self.logger = logger
        self.logSink = nil
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
        fatalError("step 5+")
    }

    public nonisolated func modelDownloadProgress() -> AsyncStream<ModelDownloadProgress> {
        fatalError("step 5+")
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
