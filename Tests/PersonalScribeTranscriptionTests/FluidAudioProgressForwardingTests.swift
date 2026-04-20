import XCTest
import FluidAudio
import PersonalScribeCore
@testable import PersonalScribeTranscription

/// Step 1.2 — verify `FluidAudioTranscriber.performPrepare` forwards the
/// FluidAudio `DownloadUtils.ProgressHandler` snapshots through the public
/// `ModelDownloadProgress` stream in the expected phase order.
final class FluidAudioProgressForwardingTests: PersonalScribeTranscriptionFilesystemTestCase {
    func testPrepareForwardsFluidAudioProgressThroughModelDownloadStream() async throws {
        // Pre-seed a model directory so the current (pre-step-1.3) pre-flight
        // validator is satisfied and does NOT trigger the legacy stub
        // downloader — we are testing the load-path forwarding specifically.
        let modelRoot = try AppConfig.directory(for: BuiltInModelCatalog.parakeetTDT06Bv2)
        try TestModelArtifacts.writeValid(to: modelRoot)

        let inference = StubInferenceClient(
            scriptedLoadProgress: [
                .init(fractionCompleted: 0.1, phase: .downloading(completedFiles: 1, totalFiles: 5)),
                .init(fractionCompleted: 0.5, phase: .downloading(completedFiles: 3, totalFiles: 5)),
                .init(fractionCompleted: 0.95, phase: .compiling(modelName: "Decoder")),
            ]
        )
        let transcriber = FluidAudioTranscriber(
            downloader: StubModelDownloader(),
            inference: inference
        )

        let stream = transcriber.modelDownloadProgress()
        // Expect: .idle (initial), .downloading(0.1), .downloading(0.5),
        // .loading (from .compiling), .finished. 5 snapshots total.
        let collector: Task<[ModelDownloadProgress], Never> = Task {
            var snapshots: [ModelDownloadProgress] = []
            for await snapshot in stream {
                snapshots.append(snapshot)
                if snapshots.count == 5 { break }
            }
            return snapshots
        }

        try await transcriber.prepare()

        let snapshots = await collector.value

        XCTAssertEqual(snapshots.count, 5)
        XCTAssertEqual(snapshots[0].phase, .idle)

        XCTAssertEqual(snapshots[1].phase, .downloading)
        XCTAssertEqual(snapshots[1].fractionCompleted, 0.1, accuracy: 1e-9)

        XCTAssertEqual(snapshots[2].phase, .downloading)
        XCTAssertEqual(snapshots[2].fractionCompleted, 0.5, accuracy: 1e-9)

        XCTAssertEqual(snapshots[3].phase, .loading)
        XCTAssertEqual(snapshots[4].phase, .finished)
    }

    func testModelAwareTranscriberForwardsFluidAudioProgressThroughModelDownloadStream() async throws {
        let descriptor = BuiltInModelCatalog.parakeetTDTCTC110M
        let rootDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let storageLocator = ModelAwareProgressTestStorageLocator(baseDirectory: rootDirectory)
        let modelDirectory = storageLocator
            .url(for: .models)
            .appendingPathComponent(descriptor.id, isDirectory: true)
            .standardizedFileURL

        try writeValidModelArtifacts(descriptor: descriptor, to: modelDirectory)

        let inference = ModelAwareProgressStubInferenceClient(
            scriptedLoadProgress: [
                .init(fractionCompleted: 0.1, phase: .downloading(completedFiles: 1, totalFiles: 5)),
                .init(fractionCompleted: 0.5, phase: .downloading(completedFiles: 3, totalFiles: 5)),
                .init(fractionCompleted: 0.95, phase: .compiling(modelName: "Decoder")),
            ]
        )
        let transcriber = ModelAwareFluidAudioTranscriber(
            descriptor: descriptor,
            runtimeVariant: .parakeetTDTCTC110M,
            storageLocator: storageLocator,
            downloader: StubModelDownloader(),
            inference: inference
        )

        let stream = transcriber.modelDownloadProgress()
        let collector: Task<[ModelDownloadProgress], Never> = Task {
            var snapshots: [ModelDownloadProgress] = []
            for await snapshot in stream {
                snapshots.append(snapshot)
                if snapshots.count == 5 { break }
            }
            return snapshots
        }

        try await transcriber.prepare()

        let snapshots = await collector.value

        XCTAssertEqual(snapshots.count, 5)
        XCTAssertEqual(snapshots[0].phase, .idle)

        XCTAssertEqual(snapshots[1].phase, .downloading)
        XCTAssertEqual(snapshots[1].fractionCompleted, 0.1, accuracy: 1e-9)

        XCTAssertEqual(snapshots[2].phase, .downloading)
        XCTAssertEqual(snapshots[2].fractionCompleted, 0.5, accuracy: 1e-9)

        XCTAssertEqual(snapshots[3].phase, .loading)
        XCTAssertEqual(snapshots[4].phase, .finished)
    }

    private func writeValidModelArtifacts(descriptor: ModelDescriptor, to directory: URL) throws {
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        for relativePath in descriptor.requiredRelativePaths {
            let destinationURL = directory.appendingPathComponent(relativePath, isDirectory: false)
            try FileManager.default.createDirectory(
                at: destinationURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            if destinationURL.lastPathComponent == "parakeet_vocab.json" {
                let contents = descriptor.id == BuiltInModelCatalog.parakeetTDTCTC110M.id ? "[]" : "{}"
                try Data(contents.utf8).write(to: destinationURL)
            } else {
                try Data([1]).write(to: destinationURL)
            }
        }
    }
}

private struct ModelAwareProgressTestStorageLocator: StorageLocator {
    let baseDirectory: URL

    func url(for directory: ManagedDirectory) -> URL {
        baseDirectory
            .appendingPathComponent(directory.pathComponent, isDirectory: true)
            .standardizedFileURL
    }

    func ensureDirectoriesExist() throws {}
}

private actor ModelAwareProgressStubInferenceClient: ModelAwareFluidAudioInferencing {
    private let scriptedLoadProgress: [DownloadUtils.DownloadProgress]

    init(scriptedLoadProgress: [DownloadUtils.DownloadProgress]) {
        self.scriptedLoadProgress = scriptedLoadProgress
    }

    func loadModel(
        from directory: URL,
        runtimeVariant: FluidAudioRuntimeVariant,
        progressHandler: DownloadUtils.ProgressHandler?
    ) async throws {
        _ = directory
        _ = runtimeVariant
        if let progressHandler {
            for snapshot in scriptedLoadProgress {
                progressHandler(snapshot)
            }
        }
    }

    func transcribe(samples: [Float]) async throws -> FluidAudioInferenceResult {
        _ = samples
        return .init(text: "", processingDuration: .zero)
    }
}
