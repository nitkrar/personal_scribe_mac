import Foundation
import XCTest
@testable import SeshatCore
@testable import SeshatTranscription

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
        let downloader = StubModelDownloader(
            writer: { url in
                try SelectionModelArtifacts.writeValid(descriptor: descriptor, to: url)
            }
        )
        let inference = StubModelAwareInferenceClient()

        try SelectionModelArtifacts.writeValid(descriptor: descriptor, to: modelDirectory)

        let transcriber = ModelAwareFluidAudioTranscriber(
            descriptor: descriptor,
            runtimeVariant: .parakeetTDTCTC110M,
            storageLocator: storageLocator,
            downloader: downloader,
            inference: inference
        )

        try await transcriber.prepare()

        let ensureCallCount = await downloader.ensureCallCount
        let loadCallCount = await inference.loadCallCount()
        let loadedVariants = await inference.loadedVariants()
        let loadedDirectories = await inference.loadedDirectories()

        XCTAssertEqual(ensureCallCount, 0)
        XCTAssertEqual(loadCallCount, 1)
        XCTAssertEqual(loadedVariants, [.parakeetTDTCTC110M])
        XCTAssertEqual(loadedDirectories, [modelDirectory])
    }

    func testPrepareRetriesCorruptDownloadOnceThenSucceeds() async throws {
        let descriptor = BuiltInModelCatalog.parakeetTDTCTC110M
        let storageLocator = TestStorageLocator(baseDirectory: try temporaryRootDirectory())
        let downloader = RetryingSelectionModelDownloader(
            descriptor: descriptor,
            firstResult: .corrupt,
            secondResult: .valid
        )
        let inference = StubModelAwareInferenceClient()
        let transcriber = ModelAwareFluidAudioTranscriber(
            descriptor: descriptor,
            runtimeVariant: .parakeetTDTCTC110M,
            storageLocator: storageLocator,
            downloader: downloader,
            inference: inference
        )

        try await transcriber.prepare()

        let attemptCount = await downloader.attemptCount()
        let loadCallCount = await inference.loadCallCount()

        XCTAssertEqual(attemptCount, 2)
        XCTAssertEqual(loadCallCount, 1)
    }

    func testPrepareResetsProgressToIdleAfterDownloadFailure() async {
        let descriptor = BuiltInModelCatalog.parakeetTDTCTC110M
        let storageLocator = TestStorageLocator(baseDirectory: try! temporaryRootDirectory())
        let downloader = StubModelDownloader(
            scriptedProgress: [
                .init(
                    phase: .downloading,
                    fractionCompleted: 0.5,
                    receivedBytes: 50,
                    expectedBytes: 100
                )
            ],
            error: URLError(.cannotConnectToHost),
            writer: { url in
                try SelectionModelArtifacts.writeValid(descriptor: descriptor, to: url)
            }
        )
        let inference = StubModelAwareInferenceClient()
        let transcriber = ModelAwareFluidAudioTranscriber(
            descriptor: descriptor,
            runtimeVariant: .parakeetTDTCTC110M,
            storageLocator: storageLocator,
            downloader: downloader,
            inference: inference
        )

        let snapshotsTask = Task {
            var snapshots: [ModelDownloadProgress] = []

            for await snapshot in transcriber.modelDownloadProgress() {
                snapshots.append(snapshot)

                if snapshots.count > 1, snapshots.last?.phase == .idle {
                    break
                }
            }

            return snapshots
        }

        do {
            try await transcriber.prepare()
            XCTFail("Expected prepare to fail when the model download fails twice")
        } catch let error as SeshatError {
            XCTAssertEqual(error, .modelDownloadFailure)
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
        let downloader = StubModelDownloader(
            writer: { url in
                try SelectionModelArtifacts.writeValid(descriptor: descriptor, to: url)
            }
        )
        let inference = StubModelAwareInferenceClient()
        let transcriber = ModelAwareFluidAudioTranscriber(
            descriptor: descriptor,
            runtimeVariant: .parakeetTDTCTC110M,
            storageLocator: storageLocator,
            downloader: downloader,
            inference: inference
        )

        async let first: Void = transcriber.prepare()
        async let second: Void = transcriber.prepare()
        _ = try await (first, second)

        let ensureCallCount = await downloader.ensureCallCount
        let loadCallCount = await inference.loadCallCount()

        XCTAssertEqual(ensureCallCount, 1)
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

private enum SelectionModelArtifacts {
    static func writeValid(descriptor: ModelDescriptor, to directory: URL) throws {
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

    static func writeCorrupt(descriptor: ModelDescriptor, to directory: URL) throws {
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
                try Data().write(to: destinationURL)
            } else {
                try Data([1]).write(to: destinationURL)
            }
        }
    }
}

private actor StubModelAwareInferenceClient: ModelAwareFluidAudioInferencing {
    private var loadCallCountStorage = 0
    private var loadedVariantsStorage: [FluidAudioRuntimeVariant] = []
    private var loadedDirectoriesStorage: [URL] = []
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
        loadCallCountStorage += 1
        loadedVariantsStorage.append(runtimeVariant)
        loadedDirectoriesStorage.append(directory)

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

private actor RetryingSelectionModelDownloader: ModelDownloading {
    enum ResultKind {
        case corrupt
        case valid
    }

    private let descriptor: ModelDescriptor
    private let firstResult: ResultKind
    private let secondResult: ResultKind
    private var attempts = 0

    init(
        descriptor: ModelDescriptor,
        firstResult: ResultKind,
        secondResult: ResultKind
    ) {
        self.descriptor = descriptor
        self.firstResult = firstResult
        self.secondResult = secondResult
    }

    func ensureModelAvailable(
        at directory: URL,
        progress: @escaping @Sendable (ModelDownloadProgress) -> Void
    ) async throws -> URL {
        attempts += 1
        progress(
            .init(
                phase: .downloading,
                fractionCompleted: 1,
                receivedBytes: 1,
                expectedBytes: 1
            )
        )

        switch attempts == 1 ? firstResult : secondResult {
        case .corrupt:
            try SelectionModelArtifacts.writeCorrupt(descriptor: descriptor, to: directory)
        case .valid:
            try SelectionModelArtifacts.writeValid(descriptor: descriptor, to: directory)
        }

        return directory
    }

    func attemptCount() -> Int {
        attempts
    }
}
