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
