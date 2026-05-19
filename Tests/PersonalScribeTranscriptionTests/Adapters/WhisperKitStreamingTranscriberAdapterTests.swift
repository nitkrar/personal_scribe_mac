@preconcurrency import WhisperKit
import Foundation
import XCTest
@testable import PersonalScribeCore
@testable import PersonalScribeTranscription

final class WhisperKitStreamingTranscriberAdapterTests: XCTestCase {
    func testDownloadIfNeededDownloadsBundleAndTokenizerWithoutLoadingModel() async throws {
        let descriptor = BuiltInModelCatalog.whisperKitStreamingSmall216MB
        let storageLocator = WhisperKitStreamingTestStorageLocator(
            baseDirectory: try temporaryRootDirectory()
        )
        let downloader = StubWhisperKitStreamingArtifactDownloader()
        let manager = StubWhisperKitStreamingManager()
        let adapter = WhisperKitStreamingTranscriberAdapter(
            descriptor: descriptor,
            storageLocator: storageLocator,
            artifactDownloader: downloader,
            manager: manager
        )

        try await adapter.downloadIfNeeded()

        let modelLeaf = modelDirectory(for: descriptor, storageLocator: storageLocator)
        let calls = await downloader.downloadCalls()
        XCTAssertEqual(calls.count, 2)
        XCTAssertEqual(calls.first?.repoID, descriptor.repository)
        XCTAssertEqual(calls.first?.matchingPatterns, ["\(descriptor.repoFolderName)/*"])
        XCTAssertEqual(calls.first?.destination, modelLeaf)
        XCTAssertEqual(calls.last?.repoID, descriptor.tokenizerSource)
        XCTAssertEqual(
            calls.last?.destination,
            modelLeaf.appendingPathComponent("tokenizer", isDirectory: true).standardizedFileURL
        )
        let loadCallCount = await manager.loadCallCount()
        XCTAssertEqual(loadCallCount, 0)
    }

    func testPrepareLoadsModelOnceUsingSharedArtifactFolder() async throws {
        let descriptor = BuiltInModelCatalog.whisperKitStreamingSmall216MB
        let storageLocator = WhisperKitStreamingTestStorageLocator(
            baseDirectory: try temporaryRootDirectory()
        )
        let downloader = StubWhisperKitStreamingArtifactDownloader()
        let manager = StubWhisperKitStreamingManager()
        let adapter = WhisperKitStreamingTranscriberAdapter(
            descriptor: descriptor,
            storageLocator: storageLocator,
            artifactDownloader: downloader,
            manager: manager
        )

        try await adapter.prepare()
        try await adapter.prepare()

        let modelLeaf = modelDirectory(for: descriptor, storageLocator: storageLocator)
        let downloadCalls = await downloader.downloadCalls()
        let loadCallCount = await manager.loadCallCount()
        let loadCalls = await manager.loadCalls()
        XCTAssertEqual(downloadCalls.count, 2)
        XCTAssertEqual(loadCallCount, 1)
        XCTAssertEqual(
            loadCalls,
            [
                StubWhisperKitStreamingManager.LoadCall(
                    modelName: descriptor.repoFolderName,
                    modelFolder: modelLeaf,
                    tokenizerFolder: modelLeaf
                        .appendingPathComponent("tokenizer", isDirectory: true)
                        .standardizedFileURL
                )
            ]
        )
    }

    func testTranscribeEmitsStableChunkThenTrailingPartialWithoutReplay() async throws {
        let descriptor = BuiltInModelCatalog.whisperKitStreamingSmall216MB
        let storageLocator = WhisperKitStreamingTestStorageLocator(
            baseDirectory: try temporaryRootDirectory()
        )
        let downloader = StubWhisperKitStreamingArtifactDownloader()
        let manager = StubWhisperKitStreamingManager(
            appendedStates: [
                [
                    .init(
                        confirmedSegments: [],
                        unconfirmedSegments: [
                            .init(start: 0, end: 0.5, text: "hello"),
                        ]
                    ),
                ],
                [
                    .init(
                        confirmedSegments: [],
                        unconfirmedSegments: [
                            .init(start: 0, end: 0.5, text: "hello"),
                            .init(start: 0.5, end: 1.0, text: "world"),
                        ]
                    ),
                ],
                [
                    .init(
                        confirmedSegments: [
                            .init(start: 0, end: 0.5, text: "hello"),
                        ],
                        unconfirmedSegments: [
                            .init(start: 0.5, end: 1.0, text: "world"),
                            .init(start: 1.0, end: 1.5, text: "again"),
                        ]
                    ),
                ],
            ],
            finalStates: [
                .init(
                    confirmedSegments: [
                        .init(start: 0, end: 0.5, text: "hello"),
                    ],
                    unconfirmedSegments: [
                        .init(start: 0.5, end: 1.0, text: "world"),
                        .init(start: 1.0, end: 1.5, text: "again"),
                    ]
                ),
            ]
        )
        let adapter = WhisperKitStreamingTranscriberAdapter(
            descriptor: descriptor,
            storageLocator: storageLocator,
            artifactDownloader: downloader,
            manager: manager
        )
        let inputBuffer = try makePCMBuffer(sampleCount: 160)

        let events = try await collectEvents(
            from: adapter.transcribe(
                stream: makeStream(buffers: [inputBuffer, inputBuffer, inputBuffer])
            )
        )

        XCTAssertEqual(
            events,
            [
                .partial(text: "hello"),
                .partial(text: "hello world"),
                .endOfUtterance(text: "hello"),
                .partial(text: "world again"),
                .finalized(
                    TranscriptionResult(
                        text: "hello world again",
                        audioDuration: inputBuffer.duration * 3,
                        processingDuration: .zero
                    )
                ),
            ]
        )
    }

    func testTranscribeCleansUpRuntimeAfterFinalizationAndPrepareReloads() async throws {
        let descriptor = BuiltInModelCatalog.whisperKitStreamingSmall216MB
        let storageLocator = WhisperKitStreamingTestStorageLocator(
            baseDirectory: try temporaryRootDirectory()
        )
        let downloader = StubWhisperKitStreamingArtifactDownloader()
        let manager = StubWhisperKitStreamingManager(
            appendedStates: [
                [
                    .init(
                        confirmedSegments: [],
                        unconfirmedSegments: [
                            .init(start: 0, end: 0.5, text: "hello"),
                        ]
                    ),
                ],
            ],
            finalStates: [
                .init(
                    confirmedSegments: [],
                    unconfirmedSegments: [
                        .init(start: 0, end: 0.5, text: "hello"),
                    ]
                ),
            ]
        )
        let adapter = WhisperKitStreamingTranscriberAdapter(
            descriptor: descriptor,
            storageLocator: storageLocator,
            artifactDownloader: downloader,
            manager: manager
        )
        let inputBuffer = try makePCMBuffer(sampleCount: 160)

        try await adapter.prepare()
        _ = try await collectEvents(
            from: adapter.transcribe(stream: makeStream(buffers: [inputBuffer]))
        )
        try await adapter.prepare()

        let cleanupCallCount = await manager.cleanupCallCount()
        let loadCallCount = await manager.loadCallCount()
        XCTAssertEqual(cleanupCallCount, 1)
        XCTAssertEqual(loadCallCount, 2)
    }
}

private extension WhisperKitStreamingTranscriberAdapterTests {
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

private struct WhisperKitStreamingTestStorageLocator: StorageLocator {
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

private actor StubWhisperKitStreamingArtifactDownloader: WhisperKitArtifactDownloading {
    struct DownloadCall: Equatable {
        let repoID: String
        let matchingPatterns: [String]?
        let stagingDirectory: URL
        let destination: URL
    }

    private var downloadCallsStorage: [DownloadCall] = []

    func downloadAndStage(
        repoID: String,
        matchingPatterns: [String]?,
        stagingDirectory: URL,
        destination: URL,
        progressHandler: @escaping @Sendable (Progress) -> Void
    ) async throws {
        _ = progressHandler
        downloadCallsStorage.append(
            DownloadCall(
                repoID: repoID,
                matchingPatterns: matchingPatterns,
                stagingDirectory: stagingDirectory,
                destination: destination
            )
        )
        try FileManager.default.createDirectory(
            at: destination,
            withIntermediateDirectories: true
        )
    }

    func downloadCalls() -> [DownloadCall] {
        downloadCallsStorage
    }
}

private actor StubWhisperKitStreamingManager: WhisperKitStreamingManaging {
    struct LoadCall: Equatable {
        let modelName: String
        let modelFolder: URL
        let tokenizerFolder: URL
    }

    private let appendedStates: [[WhisperKitStreamingState]]
    private let finalStates: [WhisperKitStreamingState]
    private var appendIndex = 0
    private var loadCallsStorage: [LoadCall] = []
    private var cleanupCallCountStorage = 0

    init(
        appendedStates: [[WhisperKitStreamingState]] = [],
        finalStates: [WhisperKitStreamingState] = []
    ) {
        self.appendedStates = appendedStates
        self.finalStates = finalStates
    }

    func loadModel(
        modelName: String,
        modelFolder: URL,
        tokenizerFolder: URL
    ) async throws {
        loadCallsStorage.append(
            LoadCall(
                modelName: modelName,
                modelFolder: modelFolder,
                tokenizerFolder: tokenizerFolder
            )
        )
    }

    func start() async throws {}

    func appendAudioSamples(_ audioSamples: [Float]) async throws -> [WhisperKitStreamingState] {
        _ = audioSamples
        guard appendIndex < appendedStates.count else {
            return []
        }
        let states = appendedStates[appendIndex]
        appendIndex += 1
        return states
    }

    func finish() async throws -> [WhisperKitStreamingState] {
        finalStates
    }

    func cleanup() async {
        cleanupCallCountStorage += 1
    }

    func loadCallCount() -> Int {
        loadCallsStorage.count
    }

    func loadCalls() -> [LoadCall] {
        loadCallsStorage
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
