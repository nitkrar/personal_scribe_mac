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

        XCTAssertEqual(await manager.loadModelCallCount(), 1)
        XCTAssertEqual(
            await manager.loadedDirectories(),
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

    init(
        scriptedProcessActions: [[ScriptedAction]] = [],
        finalText: String = ""
    ) {
        self.scriptedProcessActions = scriptedProcessActions
        self.finalText = finalText
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

    func loadModelCallCount() -> Int {
        loadModelCallCountStorage
    }

    func loadedDirectories() -> [URL] {
        loadedDirectoriesStorage
    }
}
