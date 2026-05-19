import AVFoundation
import FluidAudio
import Foundation
import XCTest
@testable import PersonalScribeCore
@testable import PersonalScribeTranscription

final class FluidAudioStreamingTranscriberAdapterTests: XCTestCase {
    func testPartialCallbackDerivesDeltaFromLastCommittedBoundary() async throws {
        let descriptor = BuiltInModelCatalog.parakeetEou160ms
        let rootDirectory = try temporaryRootDirectory()
        let storageLocator = TestStorageLocator(baseDirectory: rootDirectory)
        let manager = StubFluidAudioStreamingManager(
            scriptedProcessActions: [
                [.partial("hello")],
                [.partial("hello world")],
                [.partial("hello world how")],
            ],
            finalText: "hello world how"
        )
        let adapter = FluidAudioStreamingTranscriberAdapter(
            descriptor: descriptor,
            storageLocator: storageLocator,
            manager: manager,
            vadBoundarySessionFactory: makeVadFactory(
                events: [nil, .speechEnded, nil]
            )
        )
        let inputBuffer = try makePCMBuffer(sampleCount: 160)

        let events = try await collectEvents(
            from: adapter.transcribe(
                stream: makeStream(buffers: [inputBuffer, inputBuffer, inputBuffer])
            )
        )

        XCTAssertEqual(events.count, 5)
        XCTAssertEqual(events[0], .partial(text: "hello"))
        XCTAssertEqual(events[1], .partial(text: "hello world"))
        XCTAssertEqual(events[2], .endOfUtterance(text: "hello world"))
        XCTAssertEqual(events[3], .partial(text: "how"))
        switch events[4] {
        case .finalized(let result):
            XCTAssertEqual(result.text, "hello world how")
            XCTAssertEqual(result.audioDuration, inputBuffer.duration * 3)
        default:
            XCTFail("Expected finalized event, got \(events[4])")
        }
    }

    func testSameBufferPartialThenSpeechEndedUsesNewestCumulative() async throws {
        let descriptor = BuiltInModelCatalog.parakeetEou160ms
        let rootDirectory = try temporaryRootDirectory()
        let storageLocator = TestStorageLocator(baseDirectory: rootDirectory)
        let manager = StubFluidAudioStreamingManager(
            scriptedProcessActions: [[.partial("hello world")]],
            finalText: "hello world"
        )
        let adapter = FluidAudioStreamingTranscriberAdapter(
            descriptor: descriptor,
            storageLocator: storageLocator,
            manager: manager,
            vadBoundarySessionFactory: makeVadFactory(events: [.speechEnded])
        )
        let inputBuffer = try makePCMBuffer(sampleCount: 160)

        let events = try await collectEvents(
            from: adapter.transcribe(stream: makeStream(buffers: [inputBuffer]))
        )

        XCTAssertEqual(events[0], .partial(text: "hello world"))
        XCTAssertEqual(events[1], .endOfUtterance(text: "hello world"))
    }

    func testFirstEndOfUtteranceHasNoLeadingSpace() async throws {
        let descriptor = BuiltInModelCatalog.parakeetEou160ms
        let rootDirectory = try temporaryRootDirectory()
        let storageLocator = TestStorageLocator(baseDirectory: rootDirectory)
        let manager = StubFluidAudioStreamingManager(
            scriptedProcessActions: [[.partial("hello")]],
            finalText: "hello"
        )
        let adapter = FluidAudioStreamingTranscriberAdapter(
            descriptor: descriptor,
            storageLocator: storageLocator,
            manager: manager,
            vadBoundarySessionFactory: makeVadFactory(events: [.speechEnded])
        )
        let inputBuffer = try makePCMBuffer(sampleCount: 160)

        let events = try await collectEvents(
            from: adapter.transcribe(stream: makeStream(buffers: [inputBuffer]))
        )

        XCTAssertEqual(events[0], .partial(text: "hello"))
        XCTAssertEqual(events[1], .endOfUtterance(text: "hello"))
    }

    func testSubsequentEndOfUtterancePrependsLeadingSpace() async throws {
        let descriptor = BuiltInModelCatalog.parakeetEou160ms
        let rootDirectory = try temporaryRootDirectory()
        let storageLocator = TestStorageLocator(baseDirectory: rootDirectory)
        let manager = StubFluidAudioStreamingManager(
            scriptedProcessActions: [
                [.partial("hello")],
                [.partial("helloworld")],
            ],
            finalText: "helloworld"
        )
        let adapter = FluidAudioStreamingTranscriberAdapter(
            descriptor: descriptor,
            storageLocator: storageLocator,
            manager: manager,
            vadBoundarySessionFactory: makeVadFactory(events: [.speechEnded, .speechEnded])
        )
        let inputBuffer = try makePCMBuffer(sampleCount: 160)

        let events = try await collectEvents(
            from: adapter.transcribe(stream: makeStream(buffers: [inputBuffer, inputBuffer]))
        )

        XCTAssertEqual(
            events.prefix(4).map { $0 },
            [
                .partial(text: "hello"),
                .endOfUtterance(text: "hello"),
                .partial(text: "world"),
                .endOfUtterance(text: " world"),
            ]
        )
    }

    func testWhitespaceOnlyDeltaStillDropped() async throws {
        let descriptor = BuiltInModelCatalog.parakeetEou160ms
        let rootDirectory = try temporaryRootDirectory()
        let storageLocator = TestStorageLocator(baseDirectory: rootDirectory)
        let manager = StubFluidAudioStreamingManager(
            scriptedProcessActions: [
                [.partial("hello")],
                [.partial("hello ")],
            ],
            finalText: "hello "
        )
        let adapter = FluidAudioStreamingTranscriberAdapter(
            descriptor: descriptor,
            storageLocator: storageLocator,
            manager: manager,
            vadBoundarySessionFactory: makeVadFactory(events: [.speechEnded, .speechEnded])
        )
        let inputBuffer = try makePCMBuffer(sampleCount: 160)

        let events = try await collectEvents(
            from: adapter.transcribe(stream: makeStream(buffers: [inputBuffer, inputBuffer]))
        )

        XCTAssertEqual(
            events.map { $0 },
            [
                .partial(text: "hello"),
                .endOfUtterance(text: "hello"),
                .finalized(
                    TranscriptionResult(
                        text: "hello ",
                        audioDuration: inputBuffer.duration * 2,
                        processingDuration: .zero
                    )
                ),
            ]
        )
    }

    func testStreamEndBeforeAnyBoundaryEmitsOnlyFinalized() async throws {
        let descriptor = BuiltInModelCatalog.parakeetEou160ms
        let rootDirectory = try temporaryRootDirectory()
        let storageLocator = TestStorageLocator(baseDirectory: rootDirectory)
        let manager = StubFluidAudioStreamingManager(
            scriptedProcessActions: [[.partial("hello world")]],
            finalText: "hello world"
        )
        let adapter = FluidAudioStreamingTranscriberAdapter(
            descriptor: descriptor,
            storageLocator: storageLocator,
            manager: manager,
            vadBoundarySessionFactory: makeVadFactory(events: [nil])
        )
        let inputBuffer = try makePCMBuffer(sampleCount: 160)

        let events = try await collectEvents(
            from: adapter.transcribe(stream: makeStream(buffers: [inputBuffer]))
        )

        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events[0], .partial(text: "hello world"))
        guard case .finalized(let result) = events[1] else {
            XCTFail("Expected finalized event, got \(events)")
            return
        }
        XCTAssertEqual(result.text, "hello world")
    }

    func testVadFactoryReturnsNilFallsBackToStreamEndBoundaryAndLogsOnce() async throws {
        let descriptor = BuiltInModelCatalog.parakeetEou160ms
        let rootDirectory = try temporaryRootDirectory()
        let storageLocator = TestStorageLocator(baseDirectory: rootDirectory)
        let manager = StubFluidAudioStreamingManager(
            scriptedProcessActions: [[.partial("hello world")]],
            finalText: "hello world"
        )
        let sink = InMemoryTestSink()
        let adapter = FluidAudioStreamingTranscriberAdapter(
            descriptor: descriptor,
            storageLocator: storageLocator,
            manager: manager,
            vadBoundarySessionFactory: { _ in nil },
            logger: makeLogger(sink: sink)
        )
        let inputBuffer = try makePCMBuffer(sampleCount: 160)

        let events = try await collectEvents(
            from: adapter.transcribe(stream: makeStream(buffers: [inputBuffer]))
        )

        XCTAssertEqual(
            events.prefix(2).map { $0 },
            [
                .partial(text: "hello world"),
                .endOfUtterance(text: "hello world"),
            ]
        )
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

    func testManagerEouCallbackIsNeverRegistered() async throws {
        let descriptor = BuiltInModelCatalog.parakeetEou160ms
        let rootDirectory = try temporaryRootDirectory()
        let storageLocator = TestStorageLocator(baseDirectory: rootDirectory)
        let manager = StubFluidAudioStreamingManager(
            scriptedProcessActions: [[.partial("hello world")]],
            finalText: "hello world"
        )
        let adapter = FluidAudioStreamingTranscriberAdapter(
            descriptor: descriptor,
            storageLocator: storageLocator,
            manager: manager,
            vadBoundarySessionFactory: makeVadFactory(events: [.speechEnded])
        )
        let inputBuffer = try makePCMBuffer(sampleCount: 160)

        _ = try await collectEvents(
            from: adapter.transcribe(stream: makeStream(buffers: [inputBuffer]))
        )

        let eouCallbackSetCount = await manager.eouCallbackSetCount()
        XCTAssertEqual(eouCallbackSetCount, 0)
    }

    func testResetRunsOnlyAtSessionStartAndEnd() async throws {
        let descriptor = BuiltInModelCatalog.parakeetEou160ms
        let rootDirectory = try temporaryRootDirectory()
        let storageLocator = TestStorageLocator(baseDirectory: rootDirectory)
        let manager = StubFluidAudioStreamingManager(
            scriptedProcessActions: [
                [.partial("hello")],
                [.partial("hello world")],
            ],
            finalText: "hello world"
        )
        let adapter = FluidAudioStreamingTranscriberAdapter(
            descriptor: descriptor,
            storageLocator: storageLocator,
            manager: manager,
            vadBoundarySessionFactory: makeVadFactory(events: [nil, .speechEnded])
        )
        let inputBuffer = try makePCMBuffer(sampleCount: 160)

        _ = try await collectEvents(
            from: adapter.transcribe(stream: makeStream(buffers: [inputBuffer, inputBuffer]))
        )

        let resetCallCount = await manager.resetCallCount()
        XCTAssertEqual(resetCallCount, 2)
    }

    func testDerivedDeltaFallsBackToLongestCommonPrefixWhenLatestDoesNotExtendCommitted() {
        let derivation = FluidAudioStreamingTranscriberAdapter.deriveDelta(
            latest: "hello word",
            committed: "hello world"
        )

        XCTAssertEqual(derivation.delta, "d")
        XCTAssertTrue(derivation.usedLongestCommonPrefixFallback)
    }

    func testAdapterLoadsModelAndExtractsBasicResultUsingStubManager() async throws {
        let descriptor = BuiltInModelCatalog.parakeetEou320ms
        let rootDirectory = try temporaryRootDirectory()
        let storageLocator = TestStorageLocator(baseDirectory: rootDirectory)
        let manager = StubFluidAudioStreamingManager(finalText: "final transcript")
        let adapter = FluidAudioStreamingTranscriberAdapter(
            descriptor: descriptor,
            storageLocator: storageLocator,
            manager: manager
        )
        let inputBuffer = try makePCMBuffer(sampleCount: 320)

        let events = try await collectEvents(
            from: adapter.transcribe(
                stream: makeStream(buffers: [inputBuffer])
            )
        )

        let loadCount = await manager.loadModelCallCount()
        XCTAssertEqual(loadCount, 1)
        let loadedDirs = await manager.loadedDirectories()
        XCTAssertEqual(
            loadedDirs,
            [
                rootDirectory
                    .appendingPathComponent(ManagedDirectory.models.pathComponent, isDirectory: true)
                    .appendingPathComponent(descriptor.repoFolderName, isDirectory: true)
                    .standardizedFileURL,
            ]
        )

        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events[0], .endOfUtterance(text: "final transcript"))
        switch events[1] {
        case .finalized(let result):
            XCTAssertEqual(result.text, "final transcript")
            XCTAssertEqual(result.audioDuration, inputBuffer.duration)
        default:
            XCTFail("Expected finalized event, got \(events[1])")
        }
    }

    func testDownloadIfNeededCallsManagerDownloadButNotLoadModels() async throws {
        let descriptor = BuiltInModelCatalog.parakeetEou160ms
        let rootDirectory = try temporaryRootDirectory()
        let storageLocator = TestStorageLocator(baseDirectory: rootDirectory)
        let manager = StubFluidAudioStreamingManager()
        let adapter = FluidAudioStreamingTranscriberAdapter(
            descriptor: descriptor,
            storageLocator: storageLocator,
            manager: manager
        )

        try await adapter.downloadIfNeeded()

        let downloadCount = await manager.downloadCallCount()
        XCTAssertEqual(downloadCount, 1)
        let loadCount = await manager.loadCallCount()
        XCTAssertEqual(loadCount, 0)

        // Adapter passes the models root to the manager — FluidAudio's
        // `DownloadUtils.downloadRepo` then appends `repo.folderName`
        // to land files at the leaf path (= descriptor.repoFolderName).
        let modelsRoot = storageLocator
            .url(for: .models)
            .standardizedFileURL
        let downloadDirs = await manager.downloadDirectories()
        XCTAssertEqual(downloadDirs, [modelsRoot])
    }

    func testPrepareCallsDownloadIfNeededBeforeLoadModels() async throws {
        let descriptor = BuiltInModelCatalog.parakeetEou160ms
        let rootDirectory = try temporaryRootDirectory()
        let storageLocator = TestStorageLocator(baseDirectory: rootDirectory)
        let manager = StubFluidAudioStreamingManager()
        let adapter = FluidAudioStreamingTranscriberAdapter(
            descriptor: descriptor,
            storageLocator: storageLocator,
            manager: manager
        )

        try await adapter.prepare()

        let downloadCount = await manager.downloadCallCount()
        XCTAssertEqual(downloadCount, 1)
        let loadCount = await manager.loadCallCount()
        XCTAssertEqual(loadCount, 1)

        let leafDirectory = storageLocator
            .url(for: .models)
            .appendingPathComponent(descriptor.repoFolderName, isDirectory: true)
            .standardizedFileURL
        let modelsRoot = storageLocator
            .url(for: .models)
            .standardizedFileURL
        let downloadDirs = await manager.downloadDirectories()
        XCTAssertEqual(downloadDirs, [modelsRoot])
        let loadedDirs = await manager.loadedDirectories()
        XCTAssertEqual(loadedDirs, [leafDirectory])
    }

    func testCleanupForwardsToManagerAndAllowsPrepareToReload() async throws {
        let descriptor = BuiltInModelCatalog.parakeetEou160ms
        let rootDirectory = try temporaryRootDirectory()
        let storageLocator = TestStorageLocator(baseDirectory: rootDirectory)
        let manager = StubFluidAudioStreamingManager()
        let adapter = FluidAudioStreamingTranscriberAdapter(
            descriptor: descriptor,
            storageLocator: storageLocator,
            manager: manager
        )

        try await adapter.prepare()
        await adapter.cleanup()
        try await adapter.prepare()

        let cleanupCount = await manager.cleanupCallCount()
        let loadCount = await manager.loadCallCount()
        XCTAssertEqual(cleanupCount, 1)
        XCTAssertEqual(
            loadCount,
            2,
            "cleanup must clear the prepared latch so a later prepare reloads the model"
        )
    }
}

private extension FluidAudioStreamingTranscriberAdapterTests {
    func temporaryRootDirectory() throws -> URL {
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

    func makePCMBuffer(sampleCount: Int) throws -> PCMBuffer {
        try PCMBuffer(
            samples: Array(repeating: 0.25, count: sampleCount),
            sampleRate: AppConfig.sampleRate,
            channelCount: AppConfig.channelCount,
            timestamp: ContinuousClock().now
        )
    }

    func makeStream(
        buffers: [PCMBuffer]
    ) -> AsyncThrowingStream<PCMBuffer, Error> {
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

    func makeVadFactory(
        events: [VadEvent?]
    ) -> VadBoundarySessionFactory {
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

        XCTFail("Timed out waiting for \(expectedCount) diagnostics messages containing '\(fragment)'")
        return await logMessages(in: sink, containing: fragment)
    }

    func logMessages(
        in sink: InMemoryTestSink,
        containing fragment: String
    ) async -> [RedactedDiagnosticsEvent] {
        await sink.snapshot().filter { $0.message.contains(fragment) }
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

private actor StubFluidAudioStreamingManager: FluidAudioStreamingEouManaging {
    enum ScriptedAction: Sendable {
        case partial(String)
        case endOfUtterance(String)
    }

    private var eouCallback: EouCallback = { _ in }
    private var partialCallback: PartialCallback = { _ in }
    private var scriptedProcessActions: [[ScriptedAction]]
    private let finalText: String
    private var loadedDirectoriesStorage: [URL] = []
    private var loadModelCallCountStorage = 0
    private var downloadDirectoriesStorage: [URL] = []
    private var cleanupCallCountStorage = 0
    private var eouCallbackSetCountStorage = 0
    private var resetCallCountStorage = 0

    init(
        scriptedProcessActions: [[ScriptedAction]] = [],
        finalText: String = ""
    ) {
        self.scriptedProcessActions = scriptedProcessActions
        self.finalText = finalText
    }

    func downloadIfNeeded(
        to directory: URL,
        progressHandler: DownloadUtils.ProgressHandler?
    ) async throws {
        downloadDirectoriesStorage.append(directory)
    }

    func loadModels(modelDir: URL) async throws {
        loadModelCallCountStorage += 1
        loadedDirectoriesStorage.append(modelDir)
    }

    func setEouCallback(_ callback: @escaping EouCallback) {
        self.eouCallback = callback
        eouCallbackSetCountStorage += 1
    }

    func setPartialCallback(_ callback: @escaping PartialCallback) {
        self.partialCallback = callback
    }

    func process(audioBuffer: AVAudioPCMBuffer) async throws -> String {
        _ = audioBuffer
        let actions = scriptedProcessActions.isEmpty ? [] : scriptedProcessActions.removeFirst()
        for action in actions {
            switch action {
            case .partial(let text):
                partialCallback(text)
            case .endOfUtterance(let text):
                eouCallback(text)
            }
        }
        return ""
    }

    func finish() async throws -> String {
        finalText
    }

    func reset() async {
        resetCallCountStorage += 1
    }

    func cleanup() async {
        cleanupCallCountStorage += 1
    }

    func loadModelCallCount() -> Int {
        loadModelCallCountStorage
    }

    func loadCallCount() -> Int {
        loadModelCallCountStorage
    }

    func loadedDirectories() -> [URL] {
        loadedDirectoriesStorage
    }

    func downloadDirectories() -> [URL] {
        downloadDirectoriesStorage
    }

    func downloadCallCount() -> Int {
        downloadDirectoriesStorage.count
    }

    func cleanupCallCount() -> Int {
        cleanupCallCountStorage
    }

    func eouCallbackSetCount() -> Int {
        eouCallbackSetCountStorage
    }

    func resetCallCount() -> Int {
        resetCallCountStorage
    }
}

private actor ScriptedVadSession {
    private var events: [VadEvent?]

    init(events: [VadEvent?]) {
        self.events = events
    }

    func next() -> VadEvent? {
        guard !events.isEmpty else {
            return nil
        }
        return events.removeFirst()
    }
}
