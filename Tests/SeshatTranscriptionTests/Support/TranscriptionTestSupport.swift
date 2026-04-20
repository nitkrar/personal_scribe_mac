import Foundation
import XCTest
import SeshatCore
@testable import SeshatTranscription

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

    static func writeCorrupt(to directory: URL) throws {
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        try Data().write(
            to: directory.appendingPathComponent("parakeet_vocab.json", isDirectory: false)
        )
    }
}

actor RecordingURLSession {
    private(set) var requests: [URLRequest] = []

    func record(_ request: URLRequest) throws {
        requests.append(request)
        throw URLError(.cannotConnectToHost)
    }
}

actor StubModelDownloader: ModelDownloading {
    private(set) var ensureCallCount = 0

    private let scriptedProgress: [ModelDownloadProgress]
    private let error: Error?
    private let recordingSession: RecordingURLSession?
    private let writer: @Sendable (URL) throws -> Void

    init(
        scriptedProgress: [ModelDownloadProgress] = [],
        error: Error? = nil,
        recordingSession: RecordingURLSession? = nil,
        writer: @escaping @Sendable (URL) throws -> Void = TestModelArtifacts.writeValid(to:)
    ) {
        self.scriptedProgress = scriptedProgress
        self.error = error
        self.recordingSession = recordingSession
        self.writer = writer
    }

    func ensureModelAvailable(
        at directory: URL,
        progress: @escaping @Sendable (ModelDownloadProgress) -> Void
    ) async throws -> URL {
        ensureCallCount += 1

        if let recordingSession {
            let descriptor = BuiltInModelCatalog.parakeetTDT06Bv2
            try await recordingSession.record(
                URLRequest(url: descriptor.resolveURL(for: descriptor.requiredRelativePaths[0]))
            )
        }

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

    private let loadError: Error?
    private let transcribeError: Error?
    private let result: FluidAudioInferenceResult

    init(
        loadError: Error? = nil,
        transcribeError: Error? = nil,
        result: FluidAudioInferenceResult = .init(
            text: "",
            processingDuration: .zero
        )
    ) {
        self.loadError = loadError
        self.transcribeError = transcribeError
        self.result = result
    }

    func loadModel(
        from directory: URL,
        runtimeVariant: FluidAudioRuntimeVariant
    ) async throws {
        _ = directory
        loadCallCount += 1
        loadedRuntimeVariants.append(runtimeVariant)

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

actor RetryingStubModelDownloader: ModelDownloading {
    enum ResultKind {
        case corrupt
        case valid
    }

    private(set) var attemptCount = 0

    private let firstResult: ResultKind
    private let secondResult: ResultKind

    init(firstResult: ResultKind, secondResult: ResultKind) {
        self.firstResult = firstResult
        self.secondResult = secondResult
    }

    func ensureModelAvailable(
        at directory: URL,
        progress: @escaping @Sendable (ModelDownloadProgress) -> Void
    ) async throws -> URL {
        attemptCount += 1
        progress(.init(phase: .downloading, fractionCompleted: 1, receivedBytes: 1, expectedBytes: 1))

        switch attemptCount == 1 ? firstResult : secondResult {
        case .corrupt:
            try TestModelArtifacts.writeCorrupt(to: directory)
        case .valid:
            try TestModelArtifacts.writeValid(to: directory)
        }

        return directory
    }
}
