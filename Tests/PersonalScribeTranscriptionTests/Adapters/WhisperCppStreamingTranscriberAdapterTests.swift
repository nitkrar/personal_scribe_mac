import Foundation
import XCTest
@testable import PersonalScribeCore
@testable import PersonalScribeTranscription

final class WhisperCppStreamingTranscriberAdapterTests: XCTestCase {
    func testPrepareDownloadsAndLoadsModelOnce() async throws {
        let descriptor = BuiltInModelCatalog.whisperCppTiny
        let storageLocator = TestStorageLocator(baseDirectory: try temporaryRootDirectory())
        let manager = StubWhisperCppStreamingManager()
        let downloader = StubWhisperCppDownloader()
        let adapter = WhisperCppStreamingTranscriberAdapter(
            descriptor: descriptor,
            storageLocator: storageLocator,
            manager: manager,
            downloader: downloader
        )

        try await adapter.prepare()
        try await adapter.prepare()

        let downloadCalls = await downloader.downloadCalls()
        XCTAssertEqual(downloadCalls.count, 1)
        XCTAssertEqual(downloadCalls.first?.remoteURL, descriptor.resolveURL(for: "ggml-tiny.bin"))
        XCTAssertEqual(
            downloadCalls.first?.temporaryURL,
            modelDirectory(for: descriptor, storageLocator: storageLocator)
                .appendingPathComponent("ggml-tiny.bin.download", isDirectory: false)
        )
        let loadedModelPaths = await manager.loadedModelPaths()
        XCTAssertEqual(
            loadedModelPaths,
            [
                modelDirectory(for: descriptor, storageLocator: storageLocator)
                    .appendingPathComponent("ggml-tiny.bin", isDirectory: false),
            ]
        )
        let loadCallCount = await manager.loadCallCount()
        XCTAssertEqual(loadCallCount, 1)
    }

    func testTranscribeEmitsPartialsAtDecodeCadence() async throws {
        let manager = StubWhisperCppStreamingManager(
            decodeResults: [
                .success([makeSegment("hello", 0, 300)]),
                .success([makeSegment("hello", 0, 300)]),
            ]
        )
        let adapter = makeAdapter(
            manager: manager,
            vadSessionFactory: makeVadFactory(events: [nil, nil])
        )
        let buffer = try makePCMBuffer(sampleCount: 4_000)

        let events = try await collectEvents(
            from: adapter.transcribe(stream: makeStream(buffers: [buffer, buffer]))
        )

        XCTAssertEqual(events[0], .partial(text: "hello"))
        XCTAssertEqual(events[1], .endOfUtterance(text: "hello"))
        guard case .finalized(let result) = events[2] else {
            return XCTFail("Expected finalized event, got \(events)")
        }
        XCTAssertEqual(result.text, "hello")
        XCTAssertEqual(result.audioDuration, buffer.duration + buffer.duration)
        let decodeCallCount = await manager.decodeCallCount()
        XCTAssertEqual(decodeCallCount, 2)
    }

    func testVadSpeechEndedFlushesStablePrefixAsEndOfUtterance() async throws {
        let manager = StubWhisperCppStreamingManager(
            decodeResults: [
                .success([makeSegment("hello", 0, 300)]),
                .success([makeSegment("hello", 0, 300)]),
                .success([]),
            ]
        )
        let adapter = makeAdapter(
            manager: manager,
            vadSessionFactory: makeVadFactory(events: [nil, .speechEnded])
        )
        let cadenceBuffer = try makePCMBuffer(sampleCount: 8_000)
        let boundaryBuffer = try makePCMBuffer(sampleCount: 160)

        let events = try await collectEvents(
            from: adapter.transcribe(stream: makeStream(buffers: [cadenceBuffer, boundaryBuffer]))
        )

        XCTAssertEqual(events[0], .partial(text: "hello"))
        XCTAssertEqual(events[1], .endOfUtterance(text: "hello"))
        guard case .finalized(let result) = events[2] else {
            return XCTFail("Expected finalized event, got \(events)")
        }
        XCTAssertEqual(result.text, "hello")
        let decodeCallCount = await manager.decodeCallCount()
        XCTAssertEqual(decodeCallCount, 3)
    }

    func testStreamEndFlushesStableChunkThenFinalizedOnce() async throws {
        let manager = StubWhisperCppStreamingManager(
            decodeResults: [
                .success([
                    makeSegment("hello", 0, 300),
                    makeSegment("world", 300, 600),
                ]),
                .success([
                    makeSegment("hello", 0, 300),
                    makeSegment("world", 300, 600),
                    makeSegment("again", 600, 900),
                ]),
                .success([
                    makeSegment("hello", 0, 300),
                    makeSegment("world", 300, 600),
                    makeSegment("again", 600, 900),
                ]),
            ]
        )
        let adapter = makeAdapter(
            manager: manager,
            vadSessionFactory: makeVadFactory(events: [nil, nil])
        )
        let buffer = try makePCMBuffer(sampleCount: 8_000)

        let events = try await collectEvents(
            from: adapter.transcribe(stream: makeStream(buffers: [buffer, buffer]))
        )

        XCTAssertEqual(events[0], .partial(text: "hello world"))
        XCTAssertEqual(events[1], .partial(text: "again"))
        XCTAssertEqual(events[2], .endOfUtterance(text: "hello world again"))
        guard case .finalized(let result) = events[3] else {
            return XCTFail("Expected finalized event, got \(events)")
        }
        XCTAssertEqual(result.text, "hello world again")
        XCTAssertEqual(result.audioDuration, buffer.duration + buffer.duration)
        let decodeCallCount = await manager.decodeCallCount()
        XCTAssertEqual(decodeCallCount, 3)
    }

    func testSilentDecodeWindowProducesNoEvents() async throws {
        let manager = StubWhisperCppStreamingManager(
            decodeResults: [.success([makeSegment("should not decode", 0, 100)])]
        )
        let adapter = makeAdapter(
            manager: manager,
            vadSessionFactory: makeVadFactory(events: [nil, nil])
        )
        let silentBuffer = try makePCMBuffer(sampleCount: 8_000, sampleValue: 0)

        let events = try await collectEvents(
            from: adapter.transcribe(stream: makeStream(buffers: [silentBuffer, silentBuffer]))
        )

        XCTAssertEqual(events.count, 1)
        guard case .finalized(let result) = events[0] else {
            return XCTFail("Expected finalized event, got \(events)")
        }
        XCTAssertEqual(result.text, "")
        let decodeCallCount = await manager.decodeCallCount()
        XCTAssertEqual(decodeCallCount, 0)
    }

    func testStablePrefixFlushCommitsOnlyConfirmedPrefixAndStripsCommittedReplay() async throws {
        let manager = StubWhisperCppStreamingManager(
            decodeResults: [
                .success([
                    makeSegment("hello", 0, 300),
                    makeSegment("world", 300, 600),
                ]),
                .success([
                    makeSegment("hello", 0, 300),
                    makeSegment("world", 300, 600),
                ]),
                .success([
                    makeSegment("hello world", 0, 600),
                    makeSegment("again", 600, 900),
                ]),
                .success([
                    makeSegment("hello world", 0, 600),
                    makeSegment("again", 600, 900),
                ]),
            ]
        )
        let adapter = makeAdapter(
            manager: manager,
            vadSessionFactory: makeVadFactory(events: [nil, .speechEnded, nil])
        )
        let cadenceBuffer = try makePCMBuffer(sampleCount: 8_000)
        let boundaryBuffer = try makePCMBuffer(sampleCount: 160)

        let events = try await collectEvents(
            from: adapter.transcribe(
                stream: makeStream(buffers: [cadenceBuffer, boundaryBuffer, cadenceBuffer])
            )
        )

        XCTAssertEqual(events[0], .partial(text: "hello world"))
        XCTAssertEqual(events[1], .endOfUtterance(text: "hello world"))
        XCTAssertEqual(events[2], .partial(text: "again"))
        XCTAssertEqual(events[3], .endOfUtterance(text: "again"))
        guard case .finalized(let result) = events[4] else {
            return XCTFail("Expected finalized event, got \(events)")
        }
        XCTAssertEqual(result.text, "hello world again")
    }

    func testCancellationStopsLoopAndFinishesStreamWithoutThrow() async throws {
        let adapter = makeAdapter(
            manager: StubWhisperCppStreamingManager(),
            vadSessionFactory: makeVadFactory(events: [nil])
        )
        let buffer = try makePCMBuffer(sampleCount: 4_000)
        let stream = makeCancellingStream(buffers: [buffer])

        let events = try await collectEvents(
            from: adapter.transcribe(stream: stream)
        )

        XCTAssertTrue(events.isEmpty)
    }

    func testDecodeFailureFinishesWithPartialFinalizedNotThrow() async throws {
        let manager = StubWhisperCppStreamingManager(
            decodeResults: [
                .success([makeSegment("hello", 0, 300)]),
                .failure(StubDecodeError.decodeFailed),
            ]
        )
        let adapter = makeAdapter(
            manager: manager,
            vadSessionFactory: makeVadFactory(events: [nil, nil])
        )
        let buffer = try makePCMBuffer(sampleCount: 8_000)

        let events = try await collectEvents(
            from: adapter.transcribe(stream: makeStream(buffers: [buffer, buffer]))
        )

        XCTAssertEqual(events[0], .partial(text: "hello"))
        guard case .finalized(let result) = events[1] else {
            return XCTFail("Expected finalized event, got \(events)")
        }
        XCTAssertEqual(result.text, "hello")
        let decodeCallCount = await manager.decodeCallCount()
        XCTAssertEqual(decodeCallCount, 2)
    }

    func testReleaseIdleResourcesUnloadsContextAfterDelay() async throws {
        let descriptor = BuiltInModelCatalog.whisperCppTiny
        let storageLocator = TestStorageLocator(baseDirectory: try temporaryRootDirectory())
        let diagnosticsSink = InMemoryTestSink()
        let manager = StubWhisperCppStreamingManager()
        let adapter = WhisperCppStreamingTranscriberAdapter(
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
        XCTAssertTrue(releaseLog.message.contains("adapter=WhisperCppStreamingTranscriberAdapter"))
        XCTAssertTrue(releaseLog.message.contains("releasedAfterMs=20"))
        XCTAssertTrue(releaseLog.message.contains("hadPrepared=true"))
        XCTAssertTrue(releaseLog.message.contains("hadInFlightPrepare=false"))
    }

    func testReleaseIdleResourcesIsCancelledIfNewSessionStartsBeforeDelay() async throws {
        let diagnosticsSink = InMemoryTestSink()
        let manager = StubWhisperCppStreamingManager()
        let adapter = WhisperCppStreamingTranscriberAdapter(
            descriptor: BuiltInModelCatalog.whisperCppTiny,
            storageLocator: TestStorageLocator(baseDirectory: try temporaryRootDirectory()),
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

    func testVadUnavailableFallsBackToStreamEndOnly() async throws {
        let sink = InMemoryTestSink()
        let manager = StubWhisperCppStreamingManager(
            decodeResults: [
                .success([makeSegment("hello", 0, 300)]),
                .success([makeSegment("hello", 0, 300)]),
            ]
        )
        let adapter = WhisperCppStreamingTranscriberAdapter(
            descriptor: BuiltInModelCatalog.whisperCppTiny,
            storageLocator: TestStorageLocator(baseDirectory: try temporaryRootDirectory()),
            manager: manager,
            downloader: StubWhisperCppDownloader(),
            vadSessionFactory: nil,
            logger: makeTranscriptionLogger(sink: sink)
        )
        let buffer = try makePCMBuffer(sampleCount: 4_000)

        let events = try await collectEvents(
            from: adapter.transcribe(stream: makeStream(buffers: [buffer, buffer]))
        )

        XCTAssertEqual(events[0], .partial(text: "hello"))
        XCTAssertEqual(events[1], .endOfUtterance(text: "hello"))
        guard case .finalized(let result) = events[2] else {
            return XCTFail("Expected finalized event, got \(events)")
        }
        XCTAssertEqual(result.text, "hello")

        _ = try await waitForTranscriptionLogMessage(
            in: sink,
            containing: "VAD boundary unavailable"
        )
        let fallbackLogs = await sink.snapshot().filter {
            $0.message.contains("VAD boundary unavailable")
        }
        XCTAssertEqual(fallbackLogs.count, 1)
    }

    func testStreamingAdapterSummaryLogIncludesExpectedFields() async throws {
        let sink = InMemoryTestSink()
        let manager = StubWhisperCppStreamingManager(
            decodeResults: [
                .success([makeSegment("hello", 0, 300)]),
                .success([makeSegment("hello", 0, 300)]),
            ]
        )
        let adapter = WhisperCppStreamingTranscriberAdapter(
            descriptor: BuiltInModelCatalog.whisperCppTiny,
            storageLocator: TestStorageLocator(baseDirectory: try temporaryRootDirectory()),
            manager: manager,
            downloader: StubWhisperCppDownloader(),
            vadSessionFactory: makeVadFactory(events: [nil, nil]),
            logger: makeTranscriptionLogger(sink: sink)
        )
        let buffer = try makePCMBuffer(sampleCount: 4_000)

        _ = try await collectEvents(
            from: adapter.transcribe(stream: makeStream(buffers: [buffer, buffer]))
        )

        let summaryLog = try await waitForTranscriptionLogMessage(
            in: sink,
            containing: "streaming_adapter_summary"
        )
        XCTAssertTrue(summaryLog.message.contains("descriptorID=whispercpp-tiny"))
        XCTAssertTrue(summaryLog.message.contains("bufferCount=2"))
        XCTAssertTrue(summaryLog.message.contains("partialCount=1"))
        XCTAssertTrue(summaryLog.message.contains("eouCount=1"))
        XCTAssertTrue(summaryLog.message.contains("outcome=completed"))
        XCTAssertTrue(summaryLog.message.contains("finalTextEmpty=false"))
        XCTAssertTrue(summaryLog.message.contains("audioDurationMs=500"))
    }
}

private extension WhisperCppStreamingTranscriberAdapterTests {
    func makeAdapter(
        descriptor: ModelDescriptor = BuiltInModelCatalog.whisperCppTiny,
        manager: StubWhisperCppStreamingManager,
        vadSessionFactory: WhisperCppStreamingVadSessionFactory? = nil
    ) -> WhisperCppStreamingTranscriberAdapter {
        WhisperCppStreamingTranscriberAdapter(
            descriptor: descriptor,
            storageLocator: TestStorageLocator(baseDirectory: try! temporaryRootDirectory()),
            manager: manager,
            downloader: StubWhisperCppDownloader(),
            vadSessionFactory: vadSessionFactory
        )
    }

    func temporaryRootDirectory() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
        }
        return root
    }

    func makePCMBuffer(
        sampleCount: Int,
        sampleRate: Double = AppConfig.sampleRate,
        channelCount: Int = AppConfig.channelCount,
        sampleValue: Float = 0.25
    ) throws -> PCMBuffer {
        try PCMBuffer(
            samples: Array(repeating: sampleValue, count: sampleCount),
            sampleRate: sampleRate,
            channelCount: channelCount,
            timestamp: ContinuousClock.now
        )
    }

    func makeSegment(
        _ text: String,
        _ startMs: Int64,
        _ endMs: Int64
    ) -> WhisperCppDecodedSegment {
        WhisperCppDecodedSegment(text: text, startMs: startMs, endMs: endMs)
    }

    func makeStream(buffers: [PCMBuffer]) -> AsyncThrowingStream<PCMBuffer, Error> {
        AsyncThrowingStream { continuation in
            for buffer in buffers {
                continuation.yield(buffer)
            }
            continuation.finish()
        }
    }

    func makeCancellingStream(
        buffers: [PCMBuffer]
    ) -> AsyncThrowingStream<PCMBuffer, Error> {
        AsyncThrowingStream { continuation in
            for buffer in buffers {
                continuation.yield(buffer)
            }
            continuation.finish(throwing: CancellationError())
        }
    }

    func collectEvents(
        from stream: AsyncThrowingStream<StreamingTranscriptionEvent, Error>
    ) async throws -> [StreamingTranscriptionEvent] {
        var events: [StreamingTranscriptionEvent] = []
        for try await event in stream {
            events.append(event)
        }
        return events
    }

    func makeVadFactory(
        events: [WhisperCppStreamingVadEvent?]
    ) -> WhisperCppStreamingVadSessionFactory {
        let session = ScriptedVadSession(events: events)
        return { _ in
            WhisperCppStreamingVadSessionHandle { _ in
                await session.next()
            }
        }
    }

    func modelDirectory(
        for descriptor: ModelDescriptor,
        storageLocator: TestStorageLocator
    ) -> URL {
        storageLocator
            .url(for: .models)
            .appendingPathComponent(descriptor.repoFolderName, isDirectory: true)
            .standardizedFileURL
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
    struct DownloadCall: Equatable {
        let remoteURL: URL
        let temporaryURL: URL
    }

    private var downloadCallsStorage: [DownloadCall] = []
    private let payload: Data

    init(payload: Data = Data([0x01, 0x02, 0x03])) {
        self.payload = payload
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
        try FileManager.default.createDirectory(
            at: temporaryURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try payload.write(to: temporaryURL)
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
}

private actor StubWhisperCppStreamingManager: WhisperCppStreamingManaging {
    private let decodeResults: [Result<[WhisperCppDecodedSegment], Error>]
    private let loadDelay: Duration
    private var decodeIndex = 0
    private var loadCallCountStorage = 0
    private var loadedModelPathsStorage: [URL] = []
    private var decodeCallCountStorage = 0
    private var cleanupCallCountStorage = 0

    init(
        decodeResults: [Result<[WhisperCppDecodedSegment], Error>] = [],
        loadDelay: Duration = .zero
    ) {
        self.decodeResults = decodeResults
        self.loadDelay = loadDelay
    }

    func loadModel(from modelFileURL: URL) async throws {
        if loadDelay > .zero {
            try await Task.sleep(for: loadDelay)
        }

        loadCallCountStorage += 1
        loadedModelPathsStorage.append(modelFileURL)
    }

    func decodeSegments(
        audioSamples: [Float],
        languageHint: String?
    ) async throws -> [WhisperCppDecodedSegment] {
        _ = audioSamples
        _ = languageHint
        decodeCallCountStorage += 1

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

    func decodeCallCount() -> Int {
        decodeCallCountStorage
    }

    func cleanupCallCount() -> Int {
        cleanupCallCountStorage
    }
}

private enum StubDecodeError: Error {
    case decodeFailed
}

private actor ScriptedVadSession {
    private var events: [WhisperCppStreamingVadEvent?]

    init(events: [WhisperCppStreamingVadEvent?]) {
        self.events = events
    }

    func next() -> WhisperCppStreamingVadEvent? {
        guard !events.isEmpty else {
            return nil
        }
        return events.removeFirst()
    }
}
