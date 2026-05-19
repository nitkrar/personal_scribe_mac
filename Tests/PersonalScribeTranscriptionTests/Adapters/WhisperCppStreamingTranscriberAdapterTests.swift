import Foundation
import XCTest
@testable import PersonalScribeCore
@testable import PersonalScribeTranscription

final class WhisperCppStreamingTranscriberAdapterTests: XCTestCase {
    func testPrepareLoadsModelFromReusedBatchArtifactLeaf() async throws {
        let descriptor = BuiltInModelCatalog.whisperCppStreamingTiny
        let rootDirectory = try temporaryRootDirectory()
        let storageLocator = TestStorageLocator(baseDirectory: rootDirectory)
        let manager = StubWhisperCppStreamingManager()
        let downloader = StubWhisperCppDownloader()
        let adapter = WhisperCppStreamingTranscriberAdapter(
            descriptor: descriptor,
            storageLocator: storageLocator,
            manager: manager,
            downloader: downloader
        )

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
    }

    func testThresholdAwareTranscribePassesProvidedThresholdToVadFactory() async throws {
        let descriptor = BuiltInModelCatalog.whisperCppStreamingTiny
        let rootDirectory = try temporaryRootDirectory()
        let storageLocator = TestStorageLocator(baseDirectory: rootDirectory)
        let thresholdRecorder = ThresholdRecorder()
        let adapter = WhisperCppStreamingTranscriberAdapter(
            descriptor: descriptor,
            storageLocator: storageLocator,
            manager: StubWhisperCppStreamingManager(
                scriptedSegments: [
                    [makeSegment("hello world", 0, 600)],
                    [makeSegment("hello world", 0, 600)],
                ]
            ),
            downloader: StubWhisperCppDownloader(),
            vadBoundarySessionFactory: { threshold in
                await thresholdRecorder.record(threshold)
                return VadSessionHandle { _ in nil }
            }
        )
        let buffer = try makePCMBuffer(sampleCount: 8_000)

        _ = try await collectEvents(
            from: adapter.transcribe(
                stream: makeStream(buffers: [buffer]),
                eouSilenceThresholdSeconds: 1.4
            )
        )

        let recordedThreshold = await thresholdRecorder.value()
        XCTAssertNotNil(recordedThreshold)
        XCTAssertEqual(recordedThreshold!, 1.4, accuracy: 0.000_1)
    }

    func testSilentDecodeWindowProducesNoEvents() async throws {
        let descriptor = BuiltInModelCatalog.whisperCppStreamingTiny
        let rootDirectory = try temporaryRootDirectory()
        let storageLocator = TestStorageLocator(baseDirectory: rootDirectory)
        let manager = StubWhisperCppStreamingManager(
            scriptedSegments: [
                [makeSegment("Thank you", 0, 300)],
                [makeSegment("Thank you", 0, 300)],
            ]
        )
        let adapter = WhisperCppStreamingTranscriberAdapter(
            descriptor: descriptor,
            storageLocator: storageLocator,
            manager: manager,
            downloader: StubWhisperCppDownloader()
        )
        let silentBuffer = try makePCMBuffer(sampleCount: 8_000, sampleValue: 0)

        let events = try await collectEvents(
            from: adapter.transcribe(stream: makeStream(buffers: [silentBuffer]))
        )

        XCTAssertEqual(events.count, 1)
        guard case .finalized(let result) = events[0] else {
            XCTFail("Expected finalized event, got \(events)")
            return
        }
        XCTAssertEqual(result.text, "")
        XCTAssertEqual(result.audioDuration, silentBuffer.duration)
        let decodeCallCount = await manager.decodeCallCount()
        XCTAssertEqual(decodeCallCount, 0)
    }

    func testSpeechEndedForcesDecodeAndFlushBeforeCadenceThreshold() async throws {
        let descriptor = BuiltInModelCatalog.whisperCppStreamingTiny
        let rootDirectory = try temporaryRootDirectory()
        let storageLocator = TestStorageLocator(baseDirectory: rootDirectory)
        let manager = StubWhisperCppStreamingManager(
            scriptedSegments: [
                [makeSegment("hello", 0, 300)],
                [makeSegment("hello", 0, 300)],
            ]
        )
        let adapter = WhisperCppStreamingTranscriberAdapter(
            descriptor: descriptor,
            storageLocator: storageLocator,
            manager: manager,
            downloader: StubWhisperCppDownloader(),
            vadBoundarySessionFactory: makeVadFactory(events: [.speechEnded])
        )
        let buffer = try makePCMBuffer(sampleCount: 160)

        let events = try await collectEvents(
            from: adapter.transcribe(stream: makeStream(buffers: [buffer]))
        )

        XCTAssertEqual(events.count, 3)
        XCTAssertEqual(events[0], StreamingTranscriptionEvent.partial(text: "hello"))
        XCTAssertEqual(events[1], StreamingTranscriptionEvent.endOfUtterance(text: "hello"))
        guard case .finalized(let result) = events[2] else {
            XCTFail("Expected finalized event, got \(events)")
            return
        }
        XCTAssertEqual(result.text, "hello")
        let decodeCallCount = await manager.decodeCallCount()
        XCTAssertEqual(decodeCallCount, 2)
    }

    func testStreamEndFlushesStableChunkThenFinalizedOnce() async throws {
        let descriptor = BuiltInModelCatalog.whisperCppStreamingTiny
        let rootDirectory = try temporaryRootDirectory()
        let storageLocator = TestStorageLocator(baseDirectory: rootDirectory)
        let adapter = WhisperCppStreamingTranscriberAdapter(
            descriptor: descriptor,
            storageLocator: storageLocator,
            manager: StubWhisperCppStreamingManager(
                scriptedSegments: [
                    [
                        makeSegment("hello", 0, 300),
                        makeSegment("world", 300, 600),
                    ],
                    [
                        makeSegment("hello", 0, 300),
                        makeSegment("world", 300, 600),
                        makeSegment("again", 600, 900),
                    ],
                    [
                        makeSegment("hello", 0, 300),
                        makeSegment("world", 300, 600),
                        makeSegment("again", 600, 900),
                    ],
                ]
            ),
            downloader: StubWhisperCppDownloader(),
            vadBoundarySessionFactory: makeVadFactory(events: [nil, nil])
        )
        let buffer = try makePCMBuffer(sampleCount: 8_000)

        let events = try await collectEvents(
            from: adapter.transcribe(stream: makeStream(buffers: [buffer, buffer]))
        )

        XCTAssertEqual(events.count, 4)
        XCTAssertEqual(events[0], StreamingTranscriptionEvent.partial(text: "hello world"))
        XCTAssertEqual(events[1], StreamingTranscriptionEvent.partial(text: "again"))
        XCTAssertEqual(
            events[2],
            StreamingTranscriptionEvent.endOfUtterance(text: "hello world again")
        )
        guard case .finalized(let result) = events[3] else {
            XCTFail("Expected finalized event, got \(events)")
            return
        }
        XCTAssertEqual(result.text, "hello world again")
        XCTAssertEqual(result.audioDuration, buffer.duration * 2)
    }

    func testRegroupedCommittedReplayDoesNotReappearInPartialOrBoundary() async throws {
        let descriptor = BuiltInModelCatalog.whisperCppStreamingTiny
        let rootDirectory = try temporaryRootDirectory()
        let storageLocator = TestStorageLocator(baseDirectory: rootDirectory)
        let adapter = WhisperCppStreamingTranscriberAdapter(
            descriptor: descriptor,
            storageLocator: storageLocator,
            manager: StubWhisperCppStreamingManager(
                scriptedSegments: [
                    [
                        makeSegment("Let's see.", 0, 300),
                        makeSegment("This is odd.", 300, 600),
                    ],
                    [
                        makeSegment("Let's see.", 0, 300),
                        makeSegment("This is odd.", 300, 600),
                    ],
                    [
                        makeSegment("let's see this is odd", 0, 600),
                        makeSegment("again", 600, 900),
                    ],
                    [
                        makeSegment("let's see this is odd", 0, 600),
                        makeSegment("again", 600, 900),
                    ],
                ]
            ),
            downloader: StubWhisperCppDownloader(),
            vadBoundarySessionFactory: makeVadFactory(events: [.speechEnded, nil])
        )
        let buffer = try makePCMBuffer(sampleCount: 8_000)

        let events = try await collectEvents(
            from: adapter.transcribe(stream: makeStream(buffers: [buffer, buffer]))
        )

        XCTAssertEqual(events.count, 5)
        XCTAssertEqual(events[0], .partial(text: "Let's see. This is odd."))
        XCTAssertEqual(events[1], .endOfUtterance(text: "Let's see. This is odd."))
        XCTAssertEqual(events[2], .partial(text: "again"))
        XCTAssertEqual(events[3], .endOfUtterance(text: "again"))
        guard case .finalized(let result) = events[4] else {
            XCTFail("Expected finalized event, got \(events)")
            return
        }
        XCTAssertEqual(result.text, "Let's see. This is odd. again")
        XCTAssertEqual(result.audioDuration, buffer.duration * 2)
    }

    func testVadUnavailableLogsOnceAndFallsBackToStreamEndBoundary() async throws {
        let descriptor = BuiltInModelCatalog.whisperCppStreamingTiny
        let rootDirectory = try temporaryRootDirectory()
        let storageLocator = TestStorageLocator(baseDirectory: rootDirectory)
        let sink = InMemoryTestSink()
        let adapter = WhisperCppStreamingTranscriberAdapter(
            descriptor: descriptor,
            storageLocator: storageLocator,
            manager: StubWhisperCppStreamingManager(
                scriptedSegments: [
                    [makeSegment("hello world", 0, 600)],
                    [makeSegment("hello world", 0, 600)],
                ]
            ),
            downloader: StubWhisperCppDownloader(),
            vadBoundarySessionFactory: { _ in nil },
            logger: makeLogger(sink: sink)
        )
        let buffer = try makePCMBuffer(sampleCount: 8_000)

        let events = try await collectEvents(
            from: adapter.transcribe(stream: makeStream(buffers: [buffer]))
        )

        XCTAssertEqual(events.count, 3)
        XCTAssertEqual(events[0], StreamingTranscriptionEvent.partial(text: "hello world"))
        XCTAssertEqual(
            events[1],
            StreamingTranscriptionEvent.endOfUtterance(text: "hello world")
        )
        guard case .finalized(let result) = events[2] else {
            XCTFail("Expected finalized event, got \(events)")
            return
        }
        XCTAssertEqual(result.text, "hello world")
        XCTAssertEqual(result.audioDuration, buffer.duration)
        _ = await waitForLogMessages(
            in: sink,
            containing: "VAD boundary unavailable",
            expectedCount: 1
        )
        let unavailableLogCount = await logMessages(
            in: sink,
            containing: "VAD boundary unavailable"
        ).count
        XCTAssertEqual(unavailableLogCount, 1)
    }

    func testMismatchedBufferShapeThrowsTranscriptionFailure() async throws {
        let descriptor = BuiltInModelCatalog.whisperCppStreamingTiny
        let rootDirectory = try temporaryRootDirectory()
        let storageLocator = TestStorageLocator(baseDirectory: rootDirectory)
        let adapter = WhisperCppStreamingTranscriberAdapter(
            descriptor: descriptor,
            storageLocator: storageLocator,
            manager: StubWhisperCppStreamingManager(),
            downloader: StubWhisperCppDownloader()
        )
        let first = try makePCMBuffer(sampleCount: 8_000, sampleRate: 16_000, channelCount: 1)
        let second = try makePCMBuffer(sampleCount: 16_000, sampleRate: 16_000, channelCount: 2)

        await XCTAssertThrowsErrorAsync(
            try await collectEvents(
                from: adapter.transcribe(stream: makeStream(buffers: [first, second]))
            )
        ) { error in
            XCTAssertEqual(error as? PersonalScribeError, .transcriptionFailure)
        }
    }
}

private extension WhisperCppStreamingTranscriberAdapterTests {
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
            timestamp: ContinuousClock().now
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

    func collectEvents(
        from stream: AsyncThrowingStream<StreamingTranscriptionEvent, Error>
    ) async throws -> [StreamingTranscriptionEvent] {
        var events: [StreamingTranscriptionEvent] = []
        for try await event in stream {
            events.append(event)
        }
        return events
    }

    func makeVadFactory(events: [VadEvent?]) -> VadBoundarySessionFactory {
        let session = ScriptedVadSession(events: events)
        return { _ in
            VadSessionHandle { samples in
                _ = samples
                return await session.next()
            }
        }
    }

    func makeLogger(sink: InMemoryTestSink) -> PersonalScribeLogger {
        PersonalScribeLogger(
            category: PersonalScribeLogCategory.transcription,
            reporter: DiagnosticsReporter(
                sinks: [sink],
                now: { Date(timeIntervalSince1970: 0) }
            )
        )
    }

    func waitForLogMessages(
        in sink: InMemoryTestSink,
        containing fragment: String,
        expectedCount: Int
    ) async -> [RedactedDiagnosticsEvent] {
        for _ in 0..<100 {
            let messages = await logMessages(in: sink, containing: fragment)
            if messages.count >= expectedCount {
                return messages
            }
            try? await Task.sleep(for: .milliseconds(10))
        }

        XCTFail(
            "Timed out waiting for \(expectedCount) diagnostics messages containing '\(fragment)'"
        )
        return await logMessages(in: sink, containing: fragment)
    }

    func logMessages(
        in sink: InMemoryTestSink,
        containing fragment: String
    ) async -> [RedactedDiagnosticsEvent] {
        await sink.snapshot().filter { $0.message.contains(fragment) }
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
    private let scriptedSegments: [[WhisperCppDecodedSegment]]
    private let decodeError: Error?
    private var decodeIndex = 0
    private var loadedModelPathsStorage: [URL] = []
    private var decodeCallCountStorage = 0
    private var lastDecodeSamplesStorage: [[Float]] = []
    private var cleanupCallCountStorage = 0

    init(
        scriptedSegments: [[WhisperCppDecodedSegment]] = [],
        decodeError: Error? = nil
    ) {
        self.scriptedSegments = scriptedSegments
        self.decodeError = decodeError
    }

    func loadModel(from modelFileURL: URL) async throws {
        loadedModelPathsStorage.append(modelFileURL)
    }

    func decodeSegments(
        audioSamples: [Float],
        languageHint: String?
    ) async throws -> [WhisperCppDecodedSegment] {
        _ = languageHint
        decodeCallCountStorage += 1
        lastDecodeSamplesStorage.append(audioSamples)
        if let decodeError {
            throw decodeError
        }
        guard decodeIndex < scriptedSegments.count else {
            return []
        }
        let segments = scriptedSegments[decodeIndex]
        decodeIndex += 1
        return segments
    }

    func cleanup() async {
        cleanupCallCountStorage += 1
    }

    func loadedModelPaths() -> [URL] {
        loadedModelPathsStorage
    }

    func decodeCallCount() -> Int {
        decodeCallCountStorage
    }
}

private actor ThresholdRecorder {
    private var stored: Double?

    func record(_ value: Double) {
        stored = value
    }

    func value() -> Double? {
        stored
    }
}

private actor ScriptedVadSession {
    private var events: [VadEvent?]

    init(events: [VadEvent?]) {
        self.events = events
    }

    func next() -> VadEvent? {
        guard !events.isEmpty else { return nil }
        return events.removeFirst()
    }
}

private func XCTAssertThrowsErrorAsync<T>(
    _ expression: @autoclosure () async throws -> T,
    _ errorHandler: (Error) -> Void = { _ in }
) async {
    do {
        _ = try await expression()
        XCTFail("Expected expression to throw")
    } catch {
        errorHandler(error)
    }
}
