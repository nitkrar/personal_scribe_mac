import Foundation
import XCTest
@testable import PersonalScribeCore
@testable import PersonalScribeTranscription

private typealias WhisperCppTranscriberAdapter = WhisperCppAdapter

final class WhisperCppAdapterTests: XCTestCase {
    func testCapabilitiesAdvertiseNoOptionalMetadataSupport() throws {
        let adapter = WhisperCppTranscriberAdapter(
            descriptor: BuiltInModelCatalog.whisperCppTiny,
            storageLocator: TestStorageLocator(baseDirectory: try temporaryRootDirectory()),
            manager: StubWhisperCppManager(),
            downloader: StubWhisperCppDownloader()
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

    func testDownloadIfNeededDownloadsSingleRequiredFileIntoNamespacedLeaf() async throws {
        let descriptor = BuiltInModelCatalog.whisperCppTiny
        let storageLocator = TestStorageLocator(baseDirectory: try temporaryRootDirectory())
        let manager = StubWhisperCppManager()
        let downloader = StubWhisperCppDownloader()
        let adapter = WhisperCppTranscriberAdapter(
            descriptor: descriptor,
            storageLocator: storageLocator,
            manager: manager,
            downloader: downloader
        )

        try await adapter.downloadIfNeeded()

        let modelLeaf = modelDirectory(for: descriptor, storageLocator: storageLocator)
        let expectedFinal = modelLeaf.appendingPathComponent("ggml-tiny.bin", isDirectory: false)
        let expectedTemp = modelLeaf.appendingPathComponent("ggml-tiny.bin.download", isDirectory: false)
        let calls = await downloader.downloadCalls()
        let loadCallCount = await manager.loadCallCount()

        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls.first?.remoteURL, descriptor.resolveURL(for: "ggml-tiny.bin"))
        XCTAssertEqual(calls.first?.temporaryURL, expectedTemp)
        XCTAssertTrue(FileManager.default.fileExists(atPath: expectedFinal.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: expectedTemp.path))
        XCTAssertEqual(loadCallCount, 0)
    }

    func testDownloadIfNeededSkipsWhenArtifactAlreadyExists() async throws {
        let descriptor = BuiltInModelCatalog.whisperCppTiny
        let storageLocator = TestStorageLocator(baseDirectory: try temporaryRootDirectory())
        try seedArtifacts(for: descriptor, storageLocator: storageLocator)
        let downloader = StubWhisperCppDownloader()
        let adapter = WhisperCppTranscriberAdapter(
            descriptor: descriptor,
            storageLocator: storageLocator,
            manager: StubWhisperCppManager(),
            downloader: downloader
        )

        try await adapter.downloadIfNeeded()

        let downloadCalls = await downloader.downloadCalls()
        XCTAssertTrue(downloadCalls.isEmpty)
    }

    func testPrepareIsIdempotent() async throws {
        let descriptor = BuiltInModelCatalog.whisperCppTiny
        let storageLocator = TestStorageLocator(baseDirectory: try temporaryRootDirectory())
        let manager = StubWhisperCppManager()
        let downloader = StubWhisperCppDownloader()
        let adapter = WhisperCppTranscriberAdapter(
            descriptor: descriptor,
            storageLocator: storageLocator,
            manager: manager,
            downloader: downloader
        )

        try await adapter.prepare()
        try await adapter.prepare()

        let downloadCalls = await downloader.downloadCalls()
        let loadCallCount = await manager.loadCallCount()
        let loadedModelPaths = await manager.loadedModelPaths()
        XCTAssertEqual(downloadCalls.count, 1)
        XCTAssertEqual(loadCallCount, 1)
        XCTAssertEqual(
            loadedModelPaths,
            [modelDirectory(for: descriptor, storageLocator: storageLocator)
                .appendingPathComponent("ggml-tiny.bin", isDirectory: false)]
        )
    }

    func testPrepareDeduplicatesConcurrentCalls() async throws {
        let descriptor = BuiltInModelCatalog.whisperCppTiny
        let storageLocator = TestStorageLocator(baseDirectory: try temporaryRootDirectory())
        let manager = StubWhisperCppManager(loadDelay: Duration.milliseconds(50))
        let adapter = WhisperCppTranscriberAdapter(
            descriptor: descriptor,
            storageLocator: storageLocator,
            manager: manager,
            downloader: StubWhisperCppDownloader()
        )

        let first = Task { try await adapter.prepare() }
        let second = Task { try await adapter.prepare() }
        _ = try await (first.value, second.value)
        let loadCallCount = await manager.loadCallCount()

        XCTAssertEqual(loadCallCount, 1)
    }

    func testPrepareFailureClearsStateForRetry() async throws {
        let descriptor = BuiltInModelCatalog.whisperCppTiny
        let storageLocator = TestStorageLocator(baseDirectory: try temporaryRootDirectory())
        let manager = StubWhisperCppManager(loadFailuresRemaining: 1)
        let adapter = WhisperCppTranscriberAdapter(
            descriptor: descriptor,
            storageLocator: storageLocator,
            manager: manager,
            downloader: StubWhisperCppDownloader()
        )

        await XCTAssertThrowsErrorAsync(try await adapter.prepare()) { error in
            XCTAssertEqual(error as? PersonalScribeError, .modelLoadFailure)
        }

        try await adapter.prepare()
        let loadCallCount = await manager.loadCallCount()

        XCTAssertEqual(loadCallCount, 2)
    }

    func testDownloadIfNeededCleansUpTempFileWhenDownloadFails() async throws {
        let descriptor = BuiltInModelCatalog.whisperCppTiny
        let storageLocator = TestStorageLocator(baseDirectory: try temporaryRootDirectory())
        let downloader = StubWhisperCppDownloader(
            failureMode: .afterWritingPartialData
        )
        let adapter = WhisperCppTranscriberAdapter(
            descriptor: descriptor,
            storageLocator: storageLocator,
            manager: StubWhisperCppManager(),
            downloader: downloader
        )

        await XCTAssertThrowsErrorAsync(try await adapter.downloadIfNeeded()) { error in
            XCTAssertEqual(error as? PersonalScribeError, .modelLoadFailure)
        }

        let modelLeaf = modelDirectory(for: descriptor, storageLocator: storageLocator)
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: modelLeaf.appendingPathComponent("ggml-tiny.bin.download").path
            )
        )
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: modelLeaf.appendingPathComponent("ggml-tiny.bin").path
            )
        )
    }

    func testDownloadIfNeededRejectsDescriptorWithMultipleRequiredPaths() async throws {
        let descriptor = ModelDescriptor(
            id: "whispercpp-invalid",
            displayName: "Invalid whisper.cpp descriptor",
            repoFolderName: "whispercpp-invalid",
            shortDescription: "Invalid test fixture.",
            architecture: "Whisper (whisper.cpp runtime)",
            repository: "ggerganov/whisper.cpp",
            revision: "main",
            requiredRelativePaths: ["ggml-tiny.bin", "ggml-small.bin"],
            approximateSizeBytes: 1,
            isEnabled: true,
            engine: .whisperCpp
        )
        let downloader = StubWhisperCppDownloader()
        let adapter = WhisperCppTranscriberAdapter(
            descriptor: descriptor,
            storageLocator: TestStorageLocator(baseDirectory: try temporaryRootDirectory()),
            manager: StubWhisperCppManager(),
            downloader: downloader
        )

        await XCTAssertThrowsErrorAsync(try await adapter.downloadIfNeeded()) { error in
            XCTAssertEqual(error as? PersonalScribeError, .modelLoadFailure)
        }
        let downloadCalls = await downloader.downloadCalls()
        XCTAssertTrue(downloadCalls.isEmpty)
    }

    func testTranscribeReturnsValueOnlyResult() async throws {
        let descriptor = BuiltInModelCatalog.whisperCppTiny
        let storageLocator = TestStorageLocator(baseDirectory: try temporaryRootDirectory())
        let manager = StubWhisperCppManager(result: WhisperCppManagerResult(text: "hello world"))
        let adapter = WhisperCppTranscriberAdapter(
            descriptor: descriptor,
            storageLocator: storageLocator,
            manager: manager,
            downloader: StubWhisperCppDownloader()
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
        let transcribeCallCount = await manager.transcribeCallCount()
        let lastSamples = await manager.lastSamples()
        XCTAssertEqual(transcribeCallCount, 1)
        XCTAssertEqual(lastSamples, audio.samples)
        assertContainsNoReferenceTypes(result)
    }

    func testTranscribeForwardsLanguageHintToManager() async throws {
        let descriptor = BuiltInModelCatalog.whisperCppTiny
        let storageLocator = TestStorageLocator(baseDirectory: try temporaryRootDirectory())
        let manager = StubWhisperCppManager(result: WhisperCppManagerResult(text: "hello world"))
        let adapter = WhisperCppTranscriberAdapter(
            descriptor: descriptor,
            storageLocator: storageLocator,
            manager: manager,
            downloader: StubWhisperCppDownloader()
        )
        let audio = try PCMBuffer(
            samples: [0.2, -0.1, 0.4, -0.2],
            sampleRate: 2_000,
            channelCount: 1,
            timestamp: ContinuousClock.now
        )

        _ = try await adapter.transcribe(audio, languageHint: "ja")

        let lastLanguageHint = await manager.lastLanguageHint()
        XCTAssertEqual(lastLanguageHint, "ja")
    }

    func testTranscribeFailureThrowsTranscriptionFailure() async throws {
        let descriptor = BuiltInModelCatalog.whisperCppTiny
        let storageLocator = TestStorageLocator(baseDirectory: try temporaryRootDirectory())
        let manager = StubWhisperCppManager(transcribeError: StubWhisperCppManager.ErrorStub.transcribeFailed)
        let adapter = WhisperCppTranscriberAdapter(
            descriptor: descriptor,
            storageLocator: storageLocator,
            manager: manager,
            downloader: StubWhisperCppDownloader()
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
        let descriptor = BuiltInModelCatalog.whisperCppTiny
        let storageLocator = TestStorageLocator(baseDirectory: try temporaryRootDirectory())
        let manager = StubWhisperCppManager()
        let adapter = WhisperCppTranscriberAdapter(
            descriptor: descriptor,
            storageLocator: storageLocator,
            manager: manager,
            downloader: StubWhisperCppDownloader()
        )

        try await adapter.prepare()
        await adapter.cleanup()
        try await adapter.prepare()
        let cleanupCallCount = await manager.cleanupCallCount()
        let loadCallCount = await manager.loadCallCount()

        XCTAssertEqual(cleanupCallCount, 1)
        XCTAssertEqual(loadCallCount, 2)
    }

    func testReleaseIdleResourcesCleansUpManagerAfterDelayAndNextPrepareReloads() async throws {
        let descriptor = BuiltInModelCatalog.whisperCppTiny
        let storageLocator = TestStorageLocator(baseDirectory: try temporaryRootDirectory())
        let diagnosticsSink = InMemoryTestSink()
        let manager = StubWhisperCppManager()
        let adapter = WhisperCppTranscriberAdapter(
            descriptor: descriptor,
            storageLocator: storageLocator,
            manager: manager,
            downloader: StubWhisperCppDownloader(),
            logger: makeTranscriptionLogger(sink: diagnosticsSink),
            idleUnloadDelay: .milliseconds(20)
        )

        try await adapter.prepare()
        await adapter.releaseIdleResources()
        try? await Task.sleep(for: .milliseconds(60))
        try await adapter.prepare()
        let cleanupCallCount = await manager.cleanupCallCount()
        let loadCallCount = await manager.loadCallCount()

        XCTAssertEqual(cleanupCallCount, 1)
        XCTAssertEqual(loadCallCount, 2)

        let releaseLog = try await waitForTranscriptionLogMessage(
            in: diagnosticsSink,
            containing: "adapter_idle_release"
        )
        XCTAssertTrue(releaseLog.message.contains("descriptorID=\(descriptor.id)"))
        XCTAssertTrue(releaseLog.message.contains("adapter=WhisperCppAdapter"))
        XCTAssertTrue(releaseLog.message.contains("releasedAfterMs=20"))
        XCTAssertTrue(releaseLog.message.contains("hadPrepared=true"))
        XCTAssertTrue(releaseLog.message.contains("hadInFlightPrepare=false"))
    }

    func testPrepareCancelsPendingIdleRelease() async throws {
        let descriptor = BuiltInModelCatalog.whisperCppTiny
        let storageLocator = TestStorageLocator(baseDirectory: try temporaryRootDirectory())
        let diagnosticsSink = InMemoryTestSink()
        let manager = StubWhisperCppManager()
        let adapter = WhisperCppTranscriberAdapter(
            descriptor: descriptor,
            storageLocator: storageLocator,
            manager: manager,
            downloader: StubWhisperCppDownloader(),
            logger: makeTranscriptionLogger(sink: diagnosticsSink),
            idleUnloadDelay: .milliseconds(20)
        )

        try await adapter.prepare()
        await adapter.releaseIdleResources()
        try? await Task.sleep(for: .milliseconds(5))
        try await adapter.prepare()
        try? await Task.sleep(for: .milliseconds(60))
        try await adapter.prepare()
        let cleanupCallCount = await manager.cleanupCallCount()
        let loadCallCount = await manager.loadCallCount()

        XCTAssertEqual(cleanupCallCount, 0)
        XCTAssertEqual(loadCallCount, 1)
        let releaseLogs = await diagnosticsSink.snapshot().filter {
            $0.message.contains("adapter_idle_release")
        }
        XCTAssertTrue(releaseLogs.isEmpty)
    }

    func testReleaseIdleResourcesIsNoOpWhenNothingPrepared() async throws {
        let descriptor = BuiltInModelCatalog.whisperCppTiny
        let storageLocator = TestStorageLocator(baseDirectory: try temporaryRootDirectory())
        let diagnosticsSink = InMemoryTestSink()
        let manager = StubWhisperCppManager()
        let adapter = WhisperCppTranscriberAdapter(
            descriptor: descriptor,
            storageLocator: storageLocator,
            manager: manager,
            downloader: StubWhisperCppDownloader(),
            logger: makeTranscriptionLogger(sink: diagnosticsSink),
            idleUnloadDelay: .milliseconds(20)
        )

        await adapter.releaseIdleResources()
        try? await Task.sleep(for: .milliseconds(60))

        let cleanupCallCount = await manager.cleanupCallCount()
        let loadCallCount = await manager.loadCallCount()
        XCTAssertEqual(cleanupCallCount, 0)
        XCTAssertEqual(loadCallCount, 0)
        let releaseLogs = await diagnosticsSink.snapshot().filter {
            $0.message.contains("adapter_idle_release")
        }
        XCTAssertTrue(releaseLogs.isEmpty)
    }

    func testBatchAndStreamingShareSameContext() async throws {
        let library = RecordingWhisperCppLibrary(
            transcribedText: "hello from batch",
            decodedSegments: [WhisperCppDecodedSegment(text: "hello", startMs: 0, endMs: 300)]
        )
        let manager = LiveWhisperCppManager(library: library)
        let storageLocator = TestStorageLocator(baseDirectory: try temporaryRootDirectory())
        let adapter = WhisperCppAdapter(
            descriptor: BuiltInModelCatalog.whisperCppTiny,
            storageLocator: storageLocator,
            manager: manager,
            downloader: StubWhisperCppDownloader()
        )
        let batchAudio = try PCMBuffer(
            samples: [0.2, -0.1, 0.4, -0.2],
            sampleRate: 2_000,
            channelCount: 1,
            timestamp: ContinuousClock.now
        )
        let streamingBuffer = try PCMBuffer(
            samples: Array(repeating: 0.25, count: 4_000),
            sampleRate: AppConfig.sampleRate,
            channelCount: AppConfig.channelCount,
            timestamp: ContinuousClock.now
        )

        _ = try await adapter.transcribe(batchAudio)
        let stream = AsyncThrowingStream<PCMBuffer, Error> { continuation in
            continuation.yield(streamingBuffer)
            continuation.yield(streamingBuffer)
            continuation.finish()
        }
        for try await _ in adapter.transcribe(stream: stream) {}

        XCTAssertEqual(library.createdModelPaths.count, 1)
        XCTAssertEqual(library.transcribeCalls.count, 1)
        XCTAssertGreaterThanOrEqual(library.decodeCalls.count, 1)
        XCTAssertEqual(
            library.transcribeCalls.first?.context,
            library.decodeCalls.first?.context
        )
    }

    func testIdleReleaseTimerCoversBothBatchAndStreamingUsage() async throws {
        let manager = StubWhisperCppManager(
            decodeResults: [
                .success([WhisperCppDecodedSegment(text: "hello", startMs: 0, endMs: 300)]),
                .success([WhisperCppDecodedSegment(text: "hello", startMs: 0, endMs: 300)]),
            ]
        )
        let adapter = WhisperCppAdapter(
            descriptor: BuiltInModelCatalog.whisperCppTiny,
            storageLocator: TestStorageLocator(baseDirectory: try temporaryRootDirectory()),
            manager: manager,
            downloader: StubWhisperCppDownloader(),
            idleUnloadDelay: .milliseconds(20)
        )
        let batchAudio = try PCMBuffer(
            samples: [0.2, -0.1, 0.4, -0.2],
            sampleRate: 2_000,
            channelCount: 1,
            timestamp: ContinuousClock.now
        )
        let streamingBuffer = try PCMBuffer(
            samples: Array(repeating: 0.25, count: 4_000),
            sampleRate: AppConfig.sampleRate,
            channelCount: AppConfig.channelCount,
            timestamp: ContinuousClock.now
        )

        _ = try await adapter.transcribe(batchAudio)
        await adapter.releaseIdleResources()
        try? await Task.sleep(for: .milliseconds(60))
        try await adapter.prepare()

        let stream = AsyncThrowingStream<PCMBuffer, Error> { continuation in
            continuation.yield(streamingBuffer)
            continuation.yield(streamingBuffer)
            continuation.finish()
        }
        for try await _ in adapter.transcribe(stream: stream) {}
        await adapter.releaseIdleResources()
        try? await Task.sleep(for: .milliseconds(60))
        try await adapter.prepare()

        let cleanupCallCount = await manager.cleanupCallCount()
        let loadCallCount = await manager.loadCallCount()
        XCTAssertEqual(cleanupCallCount, 2)
        XCTAssertEqual(loadCallCount, 3)
    }

    func testLiveManagerLoadModelPassesModelFilePathToLibrary() async throws {
        let library = RecordingWhisperCppLibrary()
        let manager = LiveWhisperCppManager(library: library)
        let modelURL = try temporaryRootDirectory()
            .appendingPathComponent("ggml-tiny.bin", isDirectory: false)
        try Data([0x01]).write(to: modelURL)

        try await manager.loadModel(from: modelURL)

        XCTAssertEqual(library.createdModelPaths, [modelURL.path])
        XCTAssertEqual(library.freedContexts, [])
    }

    func testLiveManagerCleanupFreesLoadedContext() async throws {
        let library = RecordingWhisperCppLibrary()
        let manager = LiveWhisperCppManager(library: library)
        let modelURL = try temporaryRootDirectory()
            .appendingPathComponent("ggml-tiny.bin", isDirectory: false)
        try Data([0x01]).write(to: modelURL)

        try await manager.loadModel(from: modelURL)
        await manager.cleanup()

        XCTAssertEqual(library.freedContexts, [library.contextToReturn])
    }

    func testLiveManagerTranscribeReturnsLibraryText() async throws {
        let library = RecordingWhisperCppLibrary(transcribedText: "hello from library")
        let manager = LiveWhisperCppManager(library: library)
        let modelURL = try temporaryRootDirectory()
            .appendingPathComponent("ggml-tiny.bin", isDirectory: false)
        try Data([0x01]).write(to: modelURL)

        try await manager.loadModel(from: modelURL)
        let result = try await manager.transcribe(
            audioSamples: [0.1, 0.2, 0.3],
            languageHint: nil
        )

        XCTAssertEqual(result.text, "hello from library")
        XCTAssertEqual(library.transcribeCalls.count, 1)
        XCTAssertEqual(library.transcribeCalls.first?.audioSamples, [0.1, 0.2, 0.3])
    }

    func testLiveManagerTranscribeWithNilHintFallsBackToAutoLanguage() async throws {
        let library = RecordingWhisperCppLibrary(transcribedText: "hello from library")
        let manager = LiveWhisperCppManager(library: library)
        let modelURL = try temporaryRootDirectory()
            .appendingPathComponent("ggml-tiny.bin", isDirectory: false)
        try Data([0x01]).write(to: modelURL)

        try await manager.loadModel(from: modelURL)
        _ = try await manager.transcribe(audioSamples: [0.1, 0.2, 0.3], languageHint: nil)

        XCTAssertEqual(library.transcribeCalls.first?.language, "auto")
    }

    func testLiveManagerTranscribeWithHintPassesExplicitLanguage() async throws {
        let library = RecordingWhisperCppLibrary(transcribedText: "hello from library")
        let manager = LiveWhisperCppManager(library: library)
        let modelURL = try temporaryRootDirectory()
            .appendingPathComponent("ggml-tiny.bin", isDirectory: false)
        try Data([0x01]).write(to: modelURL)

        try await manager.loadModel(from: modelURL)
        _ = try await manager.transcribe(audioSamples: [0.1, 0.2, 0.3], languageHint: "ja")

        XCTAssertEqual(library.transcribeCalls.first?.language, "ja")
    }

    private func temporaryRootDirectory() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
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
        try FileManager.default.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
        for directory in ManagedDirectory.allCases {
            try FileManager.default.createDirectory(
                at: url(for: directory),
                withIntermediateDirectories: true
            )
        }
    }
}

private actor StubWhisperCppDownloader: WhisperCppDownloading {
    enum FailureMode {
        case none
        case beforeWrite
        case afterWritingPartialData
    }

    struct DownloadCall: Equatable {
        let remoteURL: URL
        let temporaryURL: URL
    }

    private let payload: Data
    private let failureMode: FailureMode
    private var downloadCallsStorage: [DownloadCall] = []

    init(
        payload: Data = Data([0x01, 0x02, 0x03]),
        failureMode: FailureMode = .none
    ) {
        self.payload = payload
        self.failureMode = failureMode
    }

    func download(
        from remoteURL: URL,
        to temporaryURL: URL,
        progressHandler: @escaping @Sendable (ModelDownloadProgress) -> Void
    ) async throws {
        downloadCallsStorage.append(
            DownloadCall(remoteURL: remoteURL, temporaryURL: temporaryURL)
        )

        progressHandler(.downloading)

        if failureMode == .beforeWrite {
            throw StubError.downloadFailed
        }

        try FileManager.default.createDirectory(
            at: temporaryURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try payload.write(to: temporaryURL)

        if failureMode == .afterWritingPartialData {
            throw StubError.downloadFailed
        }

        progressHandler(ModelDownloadProgress(
            phase: .downloading,
            fractionCompleted: 1,
            receivedBytes: Int64(payload.count),
            expectedBytes: Int64(payload.count)
        ))
    }

    func downloadCalls() -> [DownloadCall] {
        downloadCallsStorage
    }

    private enum StubError: Error {
        case downloadFailed
    }
}

private actor StubWhisperCppManager: WhisperCppManaging {
    enum ErrorStub: Error {
        case loadFailed
        case transcribeFailed
    }

    private let result: WhisperCppManagerResult
    private let decodeResults: [Result<[WhisperCppDecodedSegment], Error>]
    private let loadDelay: Duration
    private let transcribeError: Error?
    private var loadFailuresRemaining: Int
    private var loadCallCountStorage = 0
    private var loadedModelPathsStorage: [URL] = []
    private var transcribeCallCountStorage = 0
    private var decodeIndex = 0
    private var lastSamplesStorage: [Float] = []
    private var lastLanguageHintStorage: String?
    private var cleanupCallCountStorage = 0

    init(
        result: WhisperCppManagerResult = WhisperCppManagerResult(text: ""),
        decodeResults: [Result<[WhisperCppDecodedSegment], Error>] = [],
        loadFailuresRemaining: Int = 0,
        transcribeError: Error? = nil,
        loadDelay: Duration = .zero
    ) {
        self.result = result
        self.decodeResults = decodeResults
        self.loadFailuresRemaining = loadFailuresRemaining
        self.transcribeError = transcribeError
        self.loadDelay = loadDelay
    }

    func loadModel(from modelFileURL: URL) async throws {
        if loadDelay > .zero {
            try await Task.sleep(for: loadDelay)
        }

        loadCallCountStorage += 1
        loadedModelPathsStorage.append(modelFileURL)

        if loadFailuresRemaining > 0 {
            loadFailuresRemaining -= 1
            throw ErrorStub.loadFailed
        }
    }

    func transcribe(
        audioSamples: [Float],
        languageHint: String?
    ) async throws -> WhisperCppManagerResult {
        transcribeCallCountStorage += 1
        lastSamplesStorage = audioSamples
        lastLanguageHintStorage = languageHint

        if let transcribeError {
            throw transcribeError
        }

        return result
    }

    func decodeSegments(
        audioSamples: [Float],
        languageHint: String?
    ) async throws -> [WhisperCppDecodedSegment] {
        _ = audioSamples
        _ = languageHint

        guard decodeIndex < decodeResults.count else {
            return []
        }

        let result = decodeResults[decodeIndex]
        decodeIndex += 1
        return try result.get()
    }

    func cleanup() async {
        cleanupCallCountStorage += 1
    }

    func loadCallCount() -> Int {
        loadCallCountStorage
    }

    func loadedModelPaths() -> [URL] {
        loadedModelPathsStorage
    }

    func transcribeCallCount() -> Int {
        transcribeCallCountStorage
    }

    func lastSamples() -> [Float] {
        lastSamplesStorage
    }

    func lastLanguageHint() -> String? {
        lastLanguageHintStorage
    }

    func cleanupCallCount() -> Int {
        cleanupCallCountStorage
    }
}

private final class RecordingWhisperCppLibrary: @unchecked Sendable, WhisperCppLibrary {
    struct TranscribeCall: Equatable {
        let context: OpaquePointer
        let audioSamples: [Float]
        let nThreads: Int32
        let language: String
    }

    struct DecodeCall: Equatable {
        let context: OpaquePointer
        let audioSamples: [Float]
        let nThreads: Int32
        let language: String
    }

    let contextToReturn = OpaquePointer(bitPattern: 0xDAD)!
    let transcribedText: String
    let decodedSegments: [WhisperCppDecodedSegment]
    var createdModelPaths: [String] = []
    var freedContexts: [OpaquePointer] = []
    var transcribeCalls: [TranscribeCall] = []
    var decodeCalls: [DecodeCall] = []

    init(
        transcribedText: String = "",
        decodedSegments: [WhisperCppDecodedSegment] = []
    ) {
        self.transcribedText = transcribedText
        self.decodedSegments = decodedSegments
    }

    func createContext(modelPath: String) throws -> OpaquePointer {
        createdModelPaths.append(modelPath)
        return contextToReturn
    }

    func freeContext(_ context: OpaquePointer) {
        freedContexts.append(context)
    }

    func transcribe(
        context: OpaquePointer,
        audioSamples: [Float],
        nThreads: Int32,
        languageHint: String?
    ) throws -> String {
        transcribeCalls.append(
            TranscribeCall(
                context: context,
                audioSamples: audioSamples,
                nThreads: nThreads,
                language: languageHint ?? "auto"
            )
        )
        return transcribedText
    }

    func decodeSegments(
        context: OpaquePointer,
        audioSamples: [Float],
        nThreads: Int32,
        languageHint: String?
    ) throws -> [WhisperCppDecodedSegment] {
        decodeCalls.append(
            DecodeCall(
                context: context,
                audioSamples: audioSamples,
                nThreads: nThreads,
                language: languageHint ?? "auto"
            )
        )
        return decodedSegments
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
        try Data([0x01]).write(to: fileURL)
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
