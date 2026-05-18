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
        let loadCallCount = await manager.loadCallCount()
        XCTAssertEqual(loadCallCount, 0)
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

        let downloadCalls = await manager.downloadCalls()
        XCTAssertTrue(downloadCalls.isEmpty)
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

        let downloadCalls = await manager.downloadCalls()
        let loadCallCount = await manager.loadCallCount()
        let loadedModelNames = await manager.loadedModelNames()
        XCTAssertEqual(downloadCalls.count, 2)
        XCTAssertEqual(loadCallCount, 1)
        XCTAssertEqual(loadedModelNames, [descriptor.repoFolderName])
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

        let downloadCalls = await manager.downloadCalls()
        let loadCallCount = await manager.loadCallCount()
        XCTAssertEqual(downloadCalls.count, 2)
        XCTAssertEqual(loadCallCount, 1)
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

        let loadCallCount = await manager.loadCallCount()
        XCTAssertEqual(loadCallCount, 2)
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
        let loadCallCount = await manager.loadCallCount()
        let transcribeCallCount = await manager.transcribeCallCount()
        let lastSamples = await manager.lastSamples()
        XCTAssertEqual(loadCallCount, 1)
        XCTAssertEqual(transcribeCallCount, 1)
        XCTAssertEqual(lastSamples, audio.samples)
    }

    func testTranscribeReturnsValueOnlyResult() async throws {
        let descriptor = BuiltInModelCatalog.whisperKitTiny
        let storageLocator = TestStorageLocator(baseDirectory: try temporaryRootDirectory())
        let manager = StubWhisperKitManager(
            result: [WhisperKitManagerResult(text: "hello world")]
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

        assertContainsNoReferenceTypes(result)
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

        let cleanupCallCount = await manager.cleanupCallCount()
        let loadCallCount = await manager.loadCallCount()
        XCTAssertEqual(cleanupCallCount, 1)
        XCTAssertEqual(loadCallCount, 2)
    }

    func testLiveManagerDownloadAndStageMovesBundleLeafIntoDestinationAndCleansStaging() async throws {
        let root = try temporaryRootDirectory()
        let stagingDirectory = root.appendingPathComponent("staging", isDirectory: true)
        let destination = root
            .appendingPathComponent("models", isDirectory: true)
            .appendingPathComponent("openai_whisper-tiny", isDirectory: true)
            .standardizedFileURL
        let relativePaths = [
            "openai_whisper-tiny/config.json",
            "openai_whisper-tiny/TextDecoder.mlmodelc/coremldata.bin",
        ]
        let hub = StubWhisperKitHubClient(
            downloadBase: stagingDirectory,
            files: [
                relativePaths[0]: Data("{}".utf8),
                relativePaths[1]: Data([0x01]),
            ]
        )
        let manager = LiveWhisperKitManager(
            hubFactory: { _ in hub },
            whisperFactory: { _ in throw LoadModelFactoryError.unexpectedFactoryUse }
        )

        try await manager.downloadAndStage(
            repoID: "argmaxinc/whisperkit-coreml",
            relativePaths: relativePaths,
            stagingDirectory: stagingDirectory,
            destination: destination,
            progressHandler: { _ in }
        )

        let snapshotRequests = await hub.snapshotRequests()
        XCTAssertEqual(
            snapshotRequests,
            [StubWhisperKitHubClient.SnapshotRequest(
                repoID: "argmaxinc/whisperkit-coreml",
                relativePaths: relativePaths
            )]
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: destination.appendingPathComponent("config.json").path
            )
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: destination
                    .appendingPathComponent("TextDecoder.mlmodelc", isDirectory: true)
                    .appendingPathComponent("coremldata.bin")
                    .path
            )
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: stagingDirectory.path))
    }

    func testLiveManagerDownloadAndStageMovesTokenizerRepoRootIntoDestinationAndCleansStaging() async throws {
        let root = try temporaryRootDirectory()
        let stagingDirectory = root.appendingPathComponent("staging", isDirectory: true)
        let destination = root
            .appendingPathComponent("models", isDirectory: true)
            .appendingPathComponent("openai_whisper-tiny", isDirectory: true)
            .appendingPathComponent("tokenizer", isDirectory: true)
            .standardizedFileURL
        let relativePaths = [
            "tokenizer.json",
            "vocab.json",
        ]
        let hub = StubWhisperKitHubClient(
            downloadBase: stagingDirectory,
            files: [
                relativePaths[0]: Data("{}".utf8),
                relativePaths[1]: Data("{}".utf8),
            ]
        )
        let manager = LiveWhisperKitManager(
            hubFactory: { _ in hub },
            whisperFactory: { _ in throw LoadModelFactoryError.unexpectedFactoryUse }
        )

        try await manager.downloadAndStage(
            repoID: "openai/whisper-tiny",
            relativePaths: relativePaths,
            stagingDirectory: stagingDirectory,
            destination: destination,
            progressHandler: { _ in }
        )

        let snapshotRequests = await hub.snapshotRequests()
        XCTAssertEqual(
            snapshotRequests,
            [StubWhisperKitHubClient.SnapshotRequest(
                repoID: "openai/whisper-tiny",
                relativePaths: relativePaths
            )]
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: destination.appendingPathComponent("tokenizer.json").path
            )
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: destination.appendingPathComponent("vocab.json").path
            )
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: stagingDirectory.path))
    }

    func testLiveManagerLoadModelPassesExplicitTokenizerFolderToWhisperFactory() async throws {
        let root = try temporaryRootDirectory()
        let modelFolder = root
            .appendingPathComponent("openai_whisper-tiny", isDirectory: true)
            .standardizedFileURL
        try FileManager.default.createDirectory(
            at: modelFolder,
            withIntermediateDirectories: true
        )
        let recorder = WhisperKitFactoryConfigRecorder()
        let manager = LiveWhisperKitManager(
            whisperFactory: { config in
                await recorder.record(
                    model: config.model,
                    modelFolder: config.modelFolder,
                    tokenizerFolder: config.tokenizerFolder,
                    load: config.load,
                    download: config.download,
                    verbose: config.verbose,
                    prewarm: config.prewarm,
                    useBackgroundDownloadSession: config.useBackgroundDownloadSession
                )
                throw LoadModelFactoryError.expected
            }
        )

        await XCTAssertThrowsErrorAsync(
            try await manager.loadModel(
                modelName: "openai_whisper-tiny",
                modelFolder: modelFolder
            )
        ) { error in
            XCTAssertEqual(error as? LoadModelFactoryError, .expected)
        }

        let snapshot = await recorder.snapshot()
        XCTAssertEqual(snapshot?.model, "openai_whisper-tiny")
        XCTAssertEqual(snapshot?.modelFolder, modelFolder.path)
        XCTAssertEqual(
            snapshot?.tokenizerFolder?.standardizedFileURL,
            modelFolder
                .appendingPathComponent("tokenizer", isDirectory: true)
                .standardizedFileURL
        )
        XCTAssertEqual(snapshot?.load, true)
        XCTAssertEqual(snapshot?.download, false)
        XCTAssertEqual(snapshot?.verbose, false)
        XCTAssertEqual(snapshot?.prewarm, false)
        XCTAssertEqual(snapshot?.useBackgroundDownloadSession, false)
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

private actor StubWhisperKitHubClient: WhisperKitHubSnapshotting {
    struct SnapshotRequest: Equatable {
        let repoID: String
        let relativePaths: [String]
    }

    private let downloadBase: URL
    private let files: [String: Data]
    private var snapshotRequestsStorage: [SnapshotRequest] = []

    init(
        downloadBase: URL,
        files: [String: Data]
    ) {
        self.downloadBase = downloadBase
        self.files = files
    }

    func snapshot(
        repoID: String,
        relativePaths: [String],
        progressHandler: @escaping @Sendable (Progress) -> Void
    ) async throws -> URL {
        snapshotRequestsStorage.append(
            SnapshotRequest(
                repoID: repoID,
                relativePaths: relativePaths
            )
        )

        let snapshotRoot = repoRoot(for: repoID)
        try FileManager.default.createDirectory(
            at: snapshotRoot,
            withIntermediateDirectories: true
        )

        for (relativePath, data) in files {
            let fileURL = appendingRelativePath(relativePath, to: snapshotRoot)
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: fileURL)
        }

        let progress = Progress(totalUnitCount: 100)
        progress.completedUnitCount = 100
        progressHandler(progress)

        return snapshotRoot
    }

    func snapshotRequests() -> [SnapshotRequest] {
        snapshotRequestsStorage
    }

    private func repoRoot(for repoID: String) -> URL {
        repoID
            .split(separator: "/")
            .reduce(
                downloadBase
                    .appendingPathComponent("models", isDirectory: true)
                    .standardizedFileURL
            ) { partial, component in
                partial.appendingPathComponent(String(component), isDirectory: true)
            }
            .standardizedFileURL
    }
}

private actor WhisperKitFactoryConfigRecorder {
    struct Snapshot: Equatable {
        let model: String?
        let modelFolder: String?
        let tokenizerFolder: URL?
        let load: Bool?
        let download: Bool
        let verbose: Bool
        let prewarm: Bool?
        let useBackgroundDownloadSession: Bool
    }

    private var snapshotStorage: Snapshot?

    func record(
        model: String?,
        modelFolder: String?,
        tokenizerFolder: URL?,
        load: Bool?,
        download: Bool,
        verbose: Bool,
        prewarm: Bool?,
        useBackgroundDownloadSession: Bool
    ) {
        snapshotStorage = Snapshot(
            model: model,
            modelFolder: modelFolder,
            tokenizerFolder: tokenizerFolder,
            load: load,
            download: download,
            verbose: verbose,
            prewarm: prewarm,
            useBackgroundDownloadSession: useBackgroundDownloadSession
        )
    }

    func snapshot() -> Snapshot? {
        snapshotStorage
    }
}

private enum LoadModelFactoryError: Error, Equatable {
    case expected
    case unexpectedFactoryUse
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

private func appendingRelativePath(_ relativePath: String, to base: URL) -> URL {
    relativePath
        .split(separator: "/")
        .reduce(base.standardizedFileURL) { partial, component in
            partial.appendingPathComponent(String(component), isDirectory: false)
        }
        .standardizedFileURL
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

private func assertContainsNoReferenceTypes(
    _ value: Any,
    path: String = "root",
    file: StaticString = #filePath,
    line: UInt = #line
) {
    let mirror = Mirror(reflecting: value)
    if mirror.displayStyle == .class {
        XCTFail("Reference type found at \(path): \(type(of: value))", file: file, line: line)
        return
    }

    for child in mirror.children {
        let label = child.label ?? "_"
        assertContainsNoReferenceTypes(
            child.value,
            path: "\(path).\(label)",
            file: file,
            line: line
        )
    }
}
