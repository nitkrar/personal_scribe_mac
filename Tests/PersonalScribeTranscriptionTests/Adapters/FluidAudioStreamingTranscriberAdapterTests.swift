import AVFoundation
import FluidAudio
import Foundation
import XCTest
@testable import PersonalScribeCore
@testable import PersonalScribeTranscription

final class FluidAudioStreamingTranscriberAdapterTests: XCTestCase {
    func testTranscribeBridgesPartialAndEouCallbacksIntoStreamingEvents() async throws {
        let descriptor = BuiltInModelCatalog.parakeetEou160ms
        let rootDirectory = try temporaryRootDirectory()
        let storageLocator = TestStorageLocator(baseDirectory: rootDirectory)
        let manager = StubFluidAudioStreamingManager(
            scriptedProcessActions: [
                [.partial("hello"), .endOfUtterance("hello there")],
            ],
            finalText: "hello there"
        )
        let adapter = FluidAudioStreamingTranscriberAdapter(
            descriptor: descriptor,
            storageLocator: storageLocator,
            manager: manager
        )
        let inputBuffer = try makePCMBuffer(sampleCount: 160)

        let events = try await collectEvents(
            from: adapter.transcribe(
                stream: makeStream(buffers: [inputBuffer])
            )
        )

        XCTAssertEqual(events.count, 3)
        XCTAssertEqual(events[0], .partial(text: "hello"))
        XCTAssertEqual(events[1], .endOfUtterance(text: "hello there"))
        switch events[2] {
        case .finalized(let result):
            XCTAssertEqual(result.text, "hello there")
            XCTAssertEqual(result.audioDuration, inputBuffer.duration)
        default:
            XCTFail("Expected finalized event, got \(events[2])")
        }
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

        XCTAssertEqual(events.count, 1)
        switch events[0] {
        case .finalized(let result):
            XCTAssertEqual(result.text, "final transcript")
            XCTAssertEqual(result.audioDuration, inputBuffer.duration)
        default:
            XCTFail("Expected finalized event, got \(events[0])")
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

    func testTranscribeLogsStreamingAdapterSummary() async throws {
        let descriptor = BuiltInModelCatalog.parakeetEou160ms
        let rootDirectory = try temporaryRootDirectory()
        let storageLocator = TestStorageLocator(baseDirectory: rootDirectory)
        let diagnosticsSink = InMemoryTestSink()
        let manager = StubFluidAudioStreamingManager(
            scriptedProcessActions: [
                [.partial("hello"), .endOfUtterance("hello world")],
            ],
            finalText: "hello world"
        )
        let adapter = FluidAudioStreamingTranscriberAdapter(
            descriptor: descriptor,
            storageLocator: storageLocator,
            manager: manager,
            logger: makeLogger(sink: diagnosticsSink)
        )

        _ = try await collectEvents(
            from: adapter.transcribe(
                stream: makeStream(buffers: [try makePCMBuffer(sampleCount: 1_600)])
            )
        )

        let summaryLog = try await waitForLogMessage(
            in: diagnosticsSink,
            containing: "streaming_adapter_summary"
        )
        XCTAssertTrue(summaryLog.message.contains("descriptorID=\(descriptor.id)"))
        XCTAssertTrue(summaryLog.message.contains("bufferCount=1"))
        XCTAssertTrue(summaryLog.message.contains("partialCount=1"))
        XCTAssertTrue(summaryLog.message.contains("eouCount=1"))
        XCTAssertTrue(summaryLog.message.contains("outcome=completed"))
        XCTAssertTrue(summaryLog.message.contains("finalTextEmpty=false"))
        XCTAssertTrue(summaryLog.message.contains("audioDurationMs=100"))
    }
}

private extension FluidAudioStreamingTranscriberAdapterTests {
    func makeLogger(sink: InMemoryTestSink) -> PersonalScribeLogger {
        PersonalScribeLogger(
            category: PersonalScribeLogCategory.transcription,
            reporter: DiagnosticsReporter(
                sinks: [sink],
                now: { Date(timeIntervalSince1970: 0) }
            )
        )
    }

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

    func waitForLogMessage(
        in sink: InMemoryTestSink,
        containing fragment: String,
        timeout: Duration = .seconds(2)
    ) async throws -> RedactedDiagnosticsEvent {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            if let message = await sink.snapshot().first(where: { $0.message.contains(fragment) }) {
                return message
            }
            try await Task.sleep(for: .milliseconds(10))
        }

        XCTFail("Timed out waiting for diagnostics message containing '\(fragment)'")
        let fallback = await sink.snapshot().first(where: { $0.message.contains(fragment) })
        return try XCTUnwrap(fallback)
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

    func reset() async {}

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
}
