import Foundation
import FluidAudio
import XCTest
@testable import PersonalScribeCore
@testable import PersonalScribeTranscription

final class ModelAwareTranscriberTests: XCTestCase {
    func testRuntimeVariantResolveMapsBuiltInDescriptors() throws {
        XCTAssertEqual(
            try FluidAudioRuntimeVariant(descriptor: BuiltInModelCatalog.parakeetTDT06Bv2),
            .parakeetTDT06Bv2
        )
        XCTAssertEqual(
            try FluidAudioRuntimeVariant(descriptor: BuiltInModelCatalog.parakeetTDT06Bv3),
            .parakeetTDT06Bv3
        )
        XCTAssertEqual(
            try FluidAudioRuntimeVariant(descriptor: BuiltInModelCatalog.parakeetTDTCTC110M),
            .parakeetTDTCTC110M
        )
    }

    func testPrepareLoads110MFromManagedModelDirectoryWithMappedRuntimeVariant() async throws {
        let descriptor = BuiltInModelCatalog.parakeetTDTCTC110M
        let rootDirectory = try temporaryRootDirectory()
        let storageLocator = TestStorageLocator(baseDirectory: rootDirectory)
        let modelDirectory = storageLocator
            .url(for: .models)
            .appendingPathComponent(descriptor.id, isDirectory: true)
            .standardizedFileURL

        let inference = StubModelAwareInferenceClient()
        let transcriber = ModelAwareFluidAudioTranscriber(
            descriptor: descriptor,
            runtimeVariant: .parakeetTDTCTC110M,
            storageLocator: storageLocator,
            inference: inference
        )

        try await transcriber.prepare()

        let loadCallCount = await inference.loadCallCount()
        let loadedVariants = await inference.loadedVariants()
        let loadedDirectories = await inference.loadedDirectories()

        XCTAssertEqual(loadCallCount, 1)
        XCTAssertEqual(loadedVariants, [.parakeetTDTCTC110M])
        XCTAssertEqual(loadedDirectories, [modelDirectory])
    }

    func testPrepareForwardsFluidAudioProgressThroughDownloadStream() async throws {
        let descriptor = BuiltInModelCatalog.parakeetTDTCTC110M
        let storageLocator = TestStorageLocator(baseDirectory: try temporaryRootDirectory())
        let inference = StubModelAwareInferenceClient(
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

    func testPrepareResetsProgressToIdleAfterLoadFailure() async {
        let descriptor = BuiltInModelCatalog.parakeetTDTCTC110M
        let storageLocator = TestStorageLocator(baseDirectory: try! temporaryRootDirectory())
        let inference = StubModelAwareInferenceClient(
            loadError: URLError(.cannotConnectToHost),
            scriptedLoadProgress: [
                .init(fractionCompleted: 0.5, phase: .downloading(completedFiles: 2, totalFiles: 4)),
            ]
        )
        let transcriber = ModelAwareFluidAudioTranscriber(
            descriptor: descriptor,
            runtimeVariant: .parakeetTDTCTC110M,
            storageLocator: storageLocator,
            inference: inference
        )

        let snapshotsTask = Task {
            var snapshots: [ModelDownloadProgress] = []
            for await snapshot in transcriber.modelDownloadProgress() {
                snapshots.append(snapshot)
                if snapshots.count > 1, snapshots.last?.phase == .idle { break }
            }
            return snapshots
        }

        do {
            try await transcriber.prepare()
            XCTFail("Expected prepare to fail when the model load throws")
        } catch let error as PersonalScribeError {
            XCTAssertEqual(error, .modelLoadFailure)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        let snapshots = await snapshotsTask.value

        XCTAssertEqual(snapshots.first?.phase, .idle)
        XCTAssertTrue(snapshots.contains(where: { $0.phase == .downloading }))
        XCTAssertEqual(snapshots.last?.phase, .idle)
    }

    func testConcurrentPrepareCallsShareOneTask() async throws {
        let descriptor = BuiltInModelCatalog.parakeetTDTCTC110M
        let storageLocator = TestStorageLocator(baseDirectory: try temporaryRootDirectory())
        let inference = StubModelAwareInferenceClient()
        let transcriber = ModelAwareFluidAudioTranscriber(
            descriptor: descriptor,
            runtimeVariant: .parakeetTDTCTC110M,
            storageLocator: storageLocator,
            inference: inference
        )

        async let first: Void = transcriber.prepare()
        async let second: Void = transcriber.prepare()
        _ = try await (first, second)

        let loadCallCount = await inference.loadCallCount()
        XCTAssertEqual(loadCallCount, 1)
    }

    private func temporaryRootDirectory() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
        }
        return root
    }
}

private struct TestStorageLocator: StorageLocator {
    let baseDirectory: URL

    func url(for directory: ManagedDirectory) -> URL {
        baseDirectory
            .appendingPathComponent(directory.pathComponent, isDirectory: true)
            .standardizedFileURL
    }

    func ensureDirectoriesExist() throws {}
}

private actor StubModelAwareInferenceClient: ModelAwareFluidAudioInferencing {
    private var loadCallCountStorage = 0
    private var loadedVariantsStorage: [FluidAudioRuntimeVariant] = []
    private var loadedDirectoriesStorage: [URL] = []
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
        loadCallCountStorage += 1
        loadedVariantsStorage.append(runtimeVariant)
        loadedDirectoriesStorage.append(directory)

        if let progressHandler {
            for snapshot in scriptedLoadProgress {
                progressHandler(snapshot)
            }
        }

        if let loadError {
            throw loadError
        }
    }

    func transcribe(samples: [Float]) async throws -> FluidAudioInferenceResult {
        _ = samples

        if let transcribeError {
            throw transcribeError
        }

        return result
    }

    func loadCallCount() -> Int {
        loadCallCountStorage
    }

    func loadedVariants() -> [FluidAudioRuntimeVariant] {
        loadedVariantsStorage
    }

    func loadedDirectories() -> [URL] {
        loadedDirectoriesStorage
    }
}
