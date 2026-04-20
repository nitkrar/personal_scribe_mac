import Foundation
import FluidAudio
import XCTest
import PersonalScribeCore
@testable import PersonalScribeTranscription

enum TestModelArtifacts {
    static func writeValid(to directory: URL) throws {
        for component in [
            "Preprocessor.mlmodelc",
            "Encoder.mlmodelc",
            "Decoder.mlmodelc",
            "JointDecision.mlmodelc",
        ] {
            let modelDirectory = directory.appendingPathComponent(component, isDirectory: true)
            try FileManager.default.createDirectory(
                at: modelDirectory,
                withIntermediateDirectories: true
            )
            try Data([1]).write(
                to: modelDirectory.appendingPathComponent("coremldata.bin", isDirectory: false)
            )
        }

        try Data("{}".utf8).write(
            to: directory.appendingPathComponent("parakeet_vocab.json", isDirectory: false)
        )
    }
}

/// Legacy downloader stub retained only for `ModelAwareFluidAudioTranscriber`
/// tests during the transcriber-downloader removal (step 1.3 → step 1.4).
/// Step 1.4 deletes this along with the `ModelDownloading` protocol.
actor StubModelDownloader: ModelDownloading {
    private(set) var ensureCallCount = 0

    private let scriptedProgress: [ModelDownloadProgress]
    private let error: Error?
    private let writer: @Sendable (URL) throws -> Void

    init(
        scriptedProgress: [ModelDownloadProgress] = [],
        error: Error? = nil,
        writer: @escaping @Sendable (URL) throws -> Void = TestModelArtifacts.writeValid(to:)
    ) {
        self.scriptedProgress = scriptedProgress
        self.error = error
        self.writer = writer
    }

    func ensureModelAvailable(
        at directory: URL,
        progress: @escaping @Sendable (ModelDownloadProgress) -> Void
    ) async throws -> URL {
        ensureCallCount += 1

        for snapshot in scriptedProgress {
            progress(snapshot)
        }

        if let error {
            throw error
        }

        try writer(directory)
        return directory
    }
}

actor StubInferenceClient: FluidAudioInferencing {
    private(set) var loadCallCount = 0
    private(set) var transcribeCallCount = 0
    private(set) var loadedRuntimeVariants: [FluidAudioRuntimeVariant] = []
    private(set) var lastReceivedSampleCount = 0
    private(set) var lastFirstSample: Float?
    private(set) var lastLastSample: Float?
    private(set) var progressHandlerCallCount = 0

    private let loadError: Error?
    private let transcribeError: Error?
    private let result: FluidAudioInferenceResult
    private let scriptedLoadProgress: [DownloadUtils.DownloadProgress]

    init(
        loadError: Error? = nil,
        transcribeError: Error? = nil,
        result: FluidAudioInferenceResult = .init(
            text: "",
            processingDuration: .zero
        ),
        scriptedLoadProgress: [DownloadUtils.DownloadProgress] = []
    ) {
        self.loadError = loadError
        self.transcribeError = transcribeError
        self.result = result
        self.scriptedLoadProgress = scriptedLoadProgress
    }

    func loadModel(
        from directory: URL,
        runtimeVariant: FluidAudioRuntimeVariant,
        progressHandler: DownloadUtils.ProgressHandler?
    ) async throws {
        _ = directory
        loadCallCount += 1
        loadedRuntimeVariants.append(runtimeVariant)

        if let progressHandler {
            for snapshot in scriptedLoadProgress {
                progressHandler(snapshot)
                progressHandlerCallCount += 1
            }
        }

        if let loadError {
            throw loadError
        }
    }

    func transcribe(samples: [Float]) async throws -> FluidAudioInferenceResult {
        transcribeCallCount += 1
        lastReceivedSampleCount = samples.count
        lastFirstSample = samples.first
        lastLastSample = samples.last

        if let transcribeError {
            throw transcribeError
        }

        return result
    }
}
