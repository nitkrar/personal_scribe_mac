import Foundation
import XCTest
@testable import PersonalScribeCore
@testable import PersonalScribeTranscription

final class WhisperKitTranscriberAdapterTests: XCTestCase {
    func testCapabilitiesAdvertiseNoOptionalMetadataSupport() throws {
        let adapter = WhisperKitTranscriberAdapter(
            descriptor: BuiltInModelCatalog.whisperKitTiny,
            storageLocator: TestStorageLocator(baseDirectory: try temporaryRootDirectory()),
            manager: StubWhisperKitManager()
        )

        XCTAssertEqual(
            adapter.capabilities,
            TranscriberCapabilities(
                providesTokenTimings: false,
                providesConfidence: false,
                providesPerformanceMetrics: false,
                providesCustomVocabulary: false
            )
        )
    }

    func testDownloadIfNeededDownloadsBundleAndTokenizer() async throws {
        let descriptor = BuiltInModelCatalog.whisperKitTiny
        let storageLocator = TestStorageLocator(baseDirectory: try temporaryRootDirectory())
        let manager = StubWhisperKitManager()
        let adapter = WhisperKitTranscriberAdapter(
            descriptor: descriptor,
            storageLocator: storageLocator,
            manager: manager
        )

        try await adapter.downloadIfNeeded()

        let modelLeaf = modelDirectory(for: descriptor, storageLocator: storageLocator)
        let calls = await manager.downloadCalls()
        XCTAssertEqual(calls.count, 2)
        XCTAssertEqual(calls.first?.repoID, descriptor.repository)
        XCTAssertEqual(calls.first?.relativePaths, expectedBundleGlobs(for: descriptor))
        XCTAssertEqual(calls.first?.destination, modelLeaf)
        XCTAssertEqual(calls.last?.repoID, descriptor.tokenizerSource)
        XCTAssertEqual(calls.last?.relativePaths, expectedTokenizerPaths(for: descriptor))
        XCTAssertEqual(
            calls.last?.destination,
            modelLeaf.appendingPathComponent("tokenizer", isDirectory: true).standardizedFileURL
        )
        XCTAssertEqual(await manager.loadCallCount(), 0)
    }

    func testDownloadIfNeededSkipsWhenArtifactsAlreadyExist() async throws {
        let descriptor = BuiltInModelCatalog.whisperKitTiny
        let storageLocator = TestStorageLocator(baseDirectory: try temporaryRootDirectory())
        try seedArtifacts(for: descriptor, storageLocator: storageLocator)
        let manager = StubWhisperKitManager()
        let adapter = WhisperKitTranscriberAdapter(
            descriptor: descriptor,
            storageLocator: storageLocator,
            manager: manager
        )

        try await adapter.downloadIfNeeded()

        XCTAssertTrue(await manager.downloadCalls().isEmpty)
    }

    func testPrepareIsIdempotent() async throws {
        let descriptor = BuiltInModelCatalog.whisperKitTiny
        let storageLocator = TestStorageLocator(baseDirectory: try temporaryRootDirectory())
        let manager = StubWhisperKitManager()
        let adapter = WhisperKitTranscriberAdapter(
            descriptor: descriptor,
            storageLocator: storageLocator,
            manager: manager
        )

        try await adapter.prepare()
        try await adapter.prepare()

        XCTAssertEqual(await manager.downloadCalls().count, 2)
        XCTAssertEqual(await manager.loadCallCount(), 1)
        XCTAssertEqual(await manager.loadedModelNames(), [descriptor.repoFolderName])
    }

    func testPrepareDeduplicatesConcurrentCalls() async throws {
        let descriptor = BuiltInModelCatalog.whisperKitTiny
        let storageLocator = TestStorageLocator(baseDirectory: try temporaryRootDirectory())
        let manager = StubWhisperKitManager(loadDelay: .milliseconds(50))
        let adapter = WhisperKitTranscriberAdapter(
            descriptor: descriptor,
            storageLocator: storageLocator,
            manager: manager
        )

        let first = Task {
            try await adapter.prepare()
        }
        let second = Task {
            try await adapter.prepare()
        }
        _ = try await (first.value, second.value)

        XCTAssertEqual(await manager.downloadCalls().count, 2)
        XCTAssertEqual(await manager.loadCallCount(), 1)
    }

    func testPrepareFailureClearsStateForRetry() async throws {
        let descriptor = BuiltInModelCatalog.whisperKitTiny
        let storageLocator = TestStorageLocator(baseDirectory: try temporaryRootDirectory())
        let manager = StubWhisperKitManager(loadFailuresRemaining: 1)
        let adapter = WhisperKitTranscriberAdapter(
            descriptor: descriptor,
            storageLocator: storageLocator,
            manager: manager
        )

        await XCTAssertThrowsErrorAsync(try await adapter.prepare()) { error in
            XCTAssertEqual(error as? PersonalScribeError, .modelLoadFailure)
        }

        try await adapter.prepare()

        XCTAssertEqual(await manager.loadCallCount(), 2)
    }

    func testDownloadIfNeededCleansUpPartialBundleWhenTokenizerDownloadFails() async throws {
        let descriptor = BuiltInModelCatalog.whisperKitTiny
        let storageLocator = TestStorageLocator(baseDirectory: try temporaryRootDirectory())
        let manager = StubWhisperKitManager(downloadFailureRepoID: descriptor.tokenizerSource)
        let adapter = WhisperKitTranscriberAdapter(
            descriptor: descriptor,
            storageLocator: storageLocator,
            manager: manager
        )

        await XCTAssertThrowsErrorAsync(try await adapter.downloadIfNeeded()) { error in
            XCTAssertEqual(error as? PersonalScribeError, .modelLoadFailure)
        }

        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: modelDirectory(for: descriptor, storageLocator: storageLocator).path
            )
        )
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: stagingRoot(for: descriptor, storageLocator: storageLocator).path
            )
        )
    }

    func testTranscribeMergesManagerResultArray() async throws {
        let descriptor = BuiltInModelCatalog.whisperKitTiny
        let storageLocator = TestStorageLocator(baseDirectory: try temporaryRootDirectory())
        let manager = StubWhisperKitManager(
            result: [
                WhisperKitManagerResult(text: "hello"),
                WhisperKitManagerResult(text: "world"),
            ]
        )
        let adapter = WhisperKitTranscriberAdapter(
            descriptor: descriptor,
            storageLocator: storageLocator,
            manager: manager
        )
        let audio = try PCMBuffer(
            samples: [0.2, -0.1, 0.4, -0.2],
            sampleRate: 2_000,
            channelCount: 1,
            timestamp: ContinuousClock.now
        )

        let result = try await adapter.transcribe(audio)

        XCTAssertEqual(result.text, "hello world")
        XCTAssertEqual(result.audioDuration, audio.duration)
        XCTAssertNil(result.confidence)
        XCTAssertNil(result.tokenTimings)
        XCTAssertNil(result.performanceMetrics)
        XCTAssertEqual(await manager.loadCallCount(), 1)
        XCTAssertEqual(await manager.transcribeCallCount(), 1)
        XCTAssertEqual(await manager.lastSamples(), audio.samples)
    }

    func testTranscribeReturnsEmptyTextForEmptyManagerResults() async throws {
        let descriptor = BuiltInModelCatalog.whisperKitTiny
        let storageLocator = TestStorageLocator(baseDirectory: try temporaryRootDirectory())
        let manager = StubWhisperKitManager(result: [])
        let adapter = WhisperKitTranscriberAdapter(
            descriptor: descriptor,
            storageLocator: storageLocator,
            manager: manager
        )
        let audio = try PCMBuffer(
            samples: [0.2, -0.1],
            sampleRate: 2_000,
            channelCount: 1,
            timestamp: ContinuousClock.now
        )

        let result = try await adapter.transcribe(audio)

        XCTAssertEqual(result.text, "")
    }

    func testTranscribeFailureThrowsTranscriptionFailure() async throws {
        let descriptor = BuiltInModelCatalog.whisperKitTiny
        let storageLocator = TestStorageLocator(baseDirectory: try temporaryRootDirectory())
        let manager = StubWhisperKitManager(transcribeError: StubWhisperKitManager.ErrorStub.transcribeFailed)
        let adapter = WhisperKitTranscriberAdapter(
            descriptor: descriptor,
            storageLocator: storageLocator,
            manager: manager
        )
        let audio = try PCMBuffer(
            samples: [0.2, -0.1],
            sampleRate: 2_000,
            channelCount: 1,
            timestamp: ContinuousClock.now
        )

        await XCTAssertThrowsErrorAsync(try await adapter.transcribe(audio)) { error in
            XCTAssertEqual(error as? PersonalScribeError, .transcriptionFailure)
        }
    }

    func testCleanupForwardsToManagerAndAllowsPrepareToReload() async throws {
        let descriptor = BuiltInModelCatalog.whisperKitTiny
        let storageLocator = TestStorageLocator(baseDirectory: try temporaryRootDirectory())
        let manager = StubWhisperKitManager()
        let adapter = WhisperKitTranscriberAdapter(
            descriptor: descriptor,
            storageLocator: storageLocator,
            manager: manager
        )

        try await adapter.prepare()
        await adapter.cleanup()
        try await adapter.prepare()

        XCTAssertEqual(await manager.cleanupCallCount(), 1)
        XCTAssertEqual(await manager.loadCallCount(), 2)
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

    func ensureDirectoriesExist() throws {
        try FileManager.default.createDirectory(
            at: baseDirectory,
            withIntermediateDirectories: true
        )
        for directory in ManagedDirectory.allCases {
            try FileManager.default.createDirectory(
                at: url(for: directory),
                withIntermediateDirectories: true
            )
        }
    }
}

private actor StubWhisperKitManager: WhisperKitManaging {
    enum ErrorStub: Error {
        case downloadFailed
        case loadFailed
        case transcribeFailed
    }

    struct DownloadCall: Equatable {
        let repoID: String
        let relativePaths: [String]?
        let stagingDirectory: URL
        let destination: URL
    }

    private let result: [WhisperKitManagerResult]
    private let downloadFailureRepoID: String?
    private let transcribeError: Error?
    private let loadDelay: Duration
    private var loadFailuresRemaining: Int
    private var downloadCallsStorage: [DownloadCall] = []
    private var loadCallCountStorage = 0
    private var loadedModelNamesStorage: [String] = []
    private var transcribeCallCountStorage = 0
    private var lastSamplesStorage: [Float] = []
    private var cleanupCallCountStorage = 0

    init(
        result: [WhisperKitManagerResult] = [],
        downloadFailureRepoID: String? = nil,
        loadFailuresRemaining: Int = 0,
        transcribeError: Error? = nil,
        loadDelay: Duration = .zero
    ) {
        self.result = result
        self.downloadFailureRepoID = downloadFailureRepoID
        self.loadFailuresRemaining = loadFailuresRemaining
        self.transcribeError = transcribeError
        self.loadDelay = loadDelay
    }

    func downloadAndStage(
        repoID: String,
        relativePaths: [String]?,
        stagingDirectory: URL,
        destination: URL,
        progressHandler: @escaping @Sendable (Progress) -> Void
    ) async throws {
        downloadCallsStorage.append(
            DownloadCall(
                repoID: repoID,
                relativePaths: relativePaths,
                stagingDirectory: stagingDirectory,
                destination: destination
            )
        )
        try FileManager.default.createDirectory(
            at: stagingDirectory,
            withIntermediateDirectories: true
        )

        let progress = Progress(totalUnitCount: 100)
        progress.completedUnitCount = 100
        progressHandler(progress)

        if let downloadFailureRepoID, downloadFailureRepoID == repoID {
            throw ErrorStub.downloadFailed
        }

        try FileManager.default.createDirectory(
            at: destination,
            withIntermediateDirectories: true
        )
        let marker = destination.appendingPathComponent("marker.txt")
        try Data(repoID.utf8).write(to: marker)
    }

    func loadModel(
        modelName: String,
        modelFolder: URL
    ) async throws {
        if loadDelay > .zero {
            try await Task.sleep(for: loadDelay)
        }

        loadCallCountStorage += 1
        loadedModelNamesStorage.append(modelName)
        XCTAssertFalse(modelFolder.path.isEmpty)

        if loadFailuresRemaining > 0 {
            loadFailuresRemaining -= 1
            throw ErrorStub.loadFailed
        }
    }

    func transcribe(audioSamples: [Float]) async throws -> [WhisperKitManagerResult] {
        transcribeCallCountStorage += 1
        lastSamplesStorage = audioSamples
        if let transcribeError {
            throw transcribeError
        }
        return result
    }

    func cleanup() async {
        cleanupCallCountStorage += 1
    }

    func downloadCalls() -> [DownloadCall] {
        downloadCallsStorage
    }

    func loadCallCount() -> Int {
        loadCallCountStorage
    }

    func loadedModelNames() -> [String] {
        loadedModelNamesStorage
    }

    func transcribeCallCount() -> Int {
        transcribeCallCountStorage
    }

    func lastSamples() -> [Float] {
        lastSamplesStorage
    }

    func cleanupCallCount() -> Int {
        cleanupCallCountStorage
    }
}

private func modelDirectory(
    for descriptor: ModelDescriptor,
    storageLocator: any StorageLocator
) -> URL {
    storageLocator
        .url(for: .models)
        .appendingPathComponent(descriptor.repoFolderName, isDirectory: true)
        .standardizedFileURL
}

private func stagingRoot(
    for descriptor: ModelDescriptor,
    storageLocator: any StorageLocator
) -> URL {
    storageLocator
        .url(for: .models)
        .appendingPathComponent(".staging", isDirectory: true)
        .appendingPathComponent(descriptor.id, isDirectory: true)
        .standardizedFileURL
}

private func expectedBundleGlobs(for descriptor: ModelDescriptor) -> [String] {
    descriptor.requiredRelativePaths
        .filter { !$0.hasPrefix("tokenizer/") }
        .map { "\(descriptor.repoFolderName)/\($0)" }
}

private func expectedTokenizerPaths(for descriptor: ModelDescriptor) -> [String] {
    descriptor.requiredRelativePaths
        .filter { $0.hasPrefix("tokenizer/") }
        .map { String($0.dropFirst("tokenizer/".count)) }
}

private func seedArtifacts(
    for descriptor: ModelDescriptor,
    storageLocator: any StorageLocator
) throws {
    let fileManager = FileManager.default
    let root = modelDirectory(for: descriptor, storageLocator: storageLocator)
    try fileManager.createDirectory(at: root, withIntermediateDirectories: true)

    for relativePath in descriptor.requiredRelativePaths {
        let fileURL = root.appendingPathComponent(relativePath, isDirectory: false)
        try fileManager.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let data: Data
        if fileURL.lastPathComponent == "coremldata.bin" {
            data = Data([0x01])
        } else if fileURL.pathExtension == "json" {
            data = Data("{}".utf8)
        } else {
            data = Data("tokenizer".utf8)
        }

        try data.write(to: fileURL)
    }
}

private func XCTAssertThrowsErrorAsync<T>(
    _ expression: @autoclosure () async throws -> T,
    _ handler: (Error) -> Void = { _ in },
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        _ = try await expression()
        XCTFail("Expected error to be thrown", file: file, line: line)
    } catch {
        handler(error)
    }
}
