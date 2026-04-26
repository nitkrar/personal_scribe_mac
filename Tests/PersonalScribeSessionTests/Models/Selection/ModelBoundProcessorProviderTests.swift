import Foundation
import XCTest
@testable import PersonalScribeCore
@testable import PersonalScribeSession

final class ModelBoundProcessorProvidingTests: XCTestCase {
    func testProtocolExposesThreeTypedAccessors() throws {
        let provider: any ModelBoundProcessorProviding = StubModelBoundProcessorProvider()

        _ = try provider.transcriber(for: BuiltInModelCatalog.parakeetTDT06Bv2)
        _ = try provider.streamingTranscriber(for: BuiltInModelCatalog.parakeetEou160ms)
        _ = try provider.diarizer(for: BuiltInModelCatalog.speakerDiarization)
    }

    func testProtocolKeepsSharedDownloadAndIsDownloaded() async throws {
        let descriptor = BuiltInModelCatalog.parakeetTDT06Bv2
        let provider = StubModelBoundProcessorProvider(
            isDownloadedValue: true
        )

        XCTAssertTrue(provider.isDownloaded(descriptor))

        final class PhaseBox: @unchecked Sendable {
            var values: [ModelDownloadProgress.Phase] = []
        }
        let emitted = PhaseBox()
        try await provider.download(descriptor) { progress in
            emitted.values.append(progress.phase)
        }
        try provider.removeDownloadedFiles(descriptor)

        XCTAssertEqual(emitted.values, [.finished])
        XCTAssertEqual(provider.downloadedDescriptorIDs, [descriptor.id])
        XCTAssertEqual(provider.removedDescriptorIDs, [descriptor.id])
    }
}

final class AdapterRecordTests: XCTestCase {
    func testRecordHoldsThreeOptionalsForOneDescriptor() {
        let descriptor = BuiltInModelCatalog.parakeetTDT06Bv2
        let record = AdapterRecord(
            descriptorID: descriptor.id,
            transcriber: StubTranscriber2()
        )

        XCTAssertEqual(record.descriptorID, descriptor.id)
        XCTAssertNotNil(record.transcriber)
        XCTAssertNil(record.streamingTranscriber)
        XCTAssertNil(record.diarizer)
    }

    func testRecordExposesUniformLifecycleAcrossThreeAdapterTypes() async throws {
        let records = [
            AdapterRecord(
                descriptorID: "batch",
                transcriber: StubTranscriber2()
            ),
            AdapterRecord(
                descriptorID: "streaming",
                streamingTranscriber: StubStreamingTranscriber()
            ),
            AdapterRecord(
                descriptorID: "diarizer",
                diarizer: StubSpeakerDiarizer()
            ),
        ]

        for record in records {
            let lifecycle: any ModelLifecycle = record.lifecycle
            try await lifecycle.prepare()

            var emitted = 0
            for await _ in lifecycle.modelDownloadProgress() {
                emitted += 1
            }
            XCTAssertEqual(emitted, 0)
        }
    }
}

final class ModelBoundProcessorProviderTests: XCTestCase {
    func testTranscriberAccessorThrowsForStreamingEngine() {
        let provider = ModelBoundProcessorProvider(
            storageLocator: TestStorageLocator.make(),
            adapterFactory: { descriptor in
                AdapterRecord(
                    descriptorID: descriptor.id,
                    streamingTranscriber: MarkerStreamingTranscriber()
                )
            }
        )

        XCTAssertThrowsError(
            try provider.transcriber(for: BuiltInModelCatalog.parakeetEou160ms)
        ) { error in
            XCTAssertEqual(
                error as? ModelSelectionError,
                .unsupportedKind(expected: .asr, actual: .streamingASR)
            )
        }
    }

    func testStreamingTranscriberAccessorThrowsForBatchEngine() {
        let provider = ModelBoundProcessorProvider(
            storageLocator: TestStorageLocator.make(),
            adapterFactory: { descriptor in
                AdapterRecord(
                    descriptorID: descriptor.id,
                    transcriber: MarkerTranscriber2()
                )
            }
        )

        XCTAssertThrowsError(
            try provider.streamingTranscriber(for: BuiltInModelCatalog.parakeetTDT06Bv2)
        ) { error in
            XCTAssertEqual(
                error as? ModelSelectionError,
                .unsupportedKind(expected: .streamingASR, actual: .asr)
            )
        }
    }

    func testDiarizerAccessorThrowsForAsrEngine() {
        let provider = ModelBoundProcessorProvider(
            storageLocator: TestStorageLocator.make(),
            adapterFactory: { descriptor in
                AdapterRecord(
                    descriptorID: descriptor.id,
                    transcriber: MarkerTranscriber2()
                )
            }
        )

        XCTAssertThrowsError(
            try provider.diarizer(for: BuiltInModelCatalog.qwen3AsrF32)
        ) { error in
            XCTAssertEqual(
                error as? ModelSelectionError,
                .unsupportedKind(expected: .diarization, actual: .asr)
            )
        }
    }

    func testSameDescriptorReturnsSharedCacheRecord() throws {
        let factoryCallCount = AtomicIntBox()
        let provider = ModelBoundProcessorProvider(
            storageLocator: TestStorageLocator.make(),
            adapterFactory: { descriptor in
                factoryCallCount.increment()
                return AdapterRecord(
                    descriptorID: descriptor.id,
                    streamingTranscriber: MarkerStreamingTranscriber()
                )
            }
        )
        let descriptor = BuiltInModelCatalog.parakeetEou160ms

        XCTAssertThrowsError(try provider.transcriber(for: descriptor)) { error in
            XCTAssertEqual(
                error as? ModelSelectionError,
                .unsupportedKind(expected: .asr, actual: .streamingASR)
            )
        }

        let first = try provider.streamingTranscriber(for: descriptor)
        let second = try provider.streamingTranscriber(for: descriptor)

        XCTAssertEqual(factoryCallCount.value, 1)
        XCTAssertTrue((first as AnyObject) === (second as AnyObject))
    }

    func testRemoveDownloadedFilesEvictsAllAdapterTypes() throws {
        let storageLocator = TestStorageLocator.make()
        let batchDescriptor = BuiltInModelCatalog.parakeetTDT06Bv2
        let streamingDescriptor = BuiltInModelCatalog.parakeetEou160ms
        let diarizerDescriptor = BuiltInModelCatalog.speakerDiarization

        let batchCallCount = AtomicIntBox()
        let streamingCallCount = AtomicIntBox()
        let diarizerCallCount = AtomicIntBox()
        let provider = ModelBoundProcessorProvider(
            storageLocator: storageLocator,
            adapterFactory: { descriptor in
                switch descriptor.id {
                case batchDescriptor.id:
                    batchCallCount.increment()
                    return AdapterRecord(
                        descriptorID: descriptor.id,
                        transcriber: MarkerTranscriber2()
                    )
                case streamingDescriptor.id:
                    streamingCallCount.increment()
                    return AdapterRecord(
                        descriptorID: descriptor.id,
                        streamingTranscriber: MarkerStreamingTranscriber()
                    )
                case diarizerDescriptor.id:
                    diarizerCallCount.increment()
                    return AdapterRecord(
                        descriptorID: descriptor.id,
                        diarizer: MarkerSpeakerDiarizer()
                    )
                default:
                    XCTFail("Unexpected descriptor: \(descriptor.id)")
                    return AdapterRecord(
                        descriptorID: descriptor.id,
                        transcriber: MarkerTranscriber2()
                    )
                }
            }
        )

        let seededBatch = try provider.transcriber(for: batchDescriptor)
        let seededStreaming = try provider.streamingTranscriber(for: streamingDescriptor)
        let seededDiarizer = try provider.diarizer(for: diarizerDescriptor)

        try makeMarkerDirectory(for: batchDescriptor, storageLocator: storageLocator)
        try makeMarkerDirectory(for: streamingDescriptor, storageLocator: storageLocator)
        try makeMarkerDirectory(for: diarizerDescriptor, storageLocator: storageLocator)

        try provider.removeDownloadedFiles(batchDescriptor)
        try provider.removeDownloadedFiles(streamingDescriptor)
        try provider.removeDownloadedFiles(diarizerDescriptor)

        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: modelDirectory(for: batchDescriptor, storageLocator: storageLocator).path
            )
        )
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: modelDirectory(for: streamingDescriptor, storageLocator: storageLocator).path
            )
        )
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: modelDirectory(for: diarizerDescriptor, storageLocator: storageLocator).path
            )
        )

        let rebuiltBatch = try provider.transcriber(for: batchDescriptor)
        let rebuiltStreaming = try provider.streamingTranscriber(for: streamingDescriptor)
        let rebuiltDiarizer = try provider.diarizer(for: diarizerDescriptor)

        XCTAssertEqual(batchCallCount.value, 2)
        XCTAssertEqual(streamingCallCount.value, 2)
        XCTAssertEqual(diarizerCallCount.value, 2)
        XCTAssertFalse((seededBatch as AnyObject) === (rebuiltBatch as AnyObject))
        XCTAssertFalse((seededStreaming as AnyObject) === (rebuiltStreaming as AnyObject))
        XCTAssertFalse((seededDiarizer as AnyObject) === (rebuiltDiarizer as AnyObject))
    }
}

private struct StubTranscriber2: Transcriber2 {
    let capabilities = TranscriberCapabilities()

    func prepare() async throws {}

    func modelDownloadProgress() -> AsyncStream<ModelDownloadProgress> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }

    func transcribe(_ audio: PCMBuffer) async throws -> TranscriptionResult {
        TranscriptionResult(
            text: "stub",
            audioDuration: .zero,
            processingDuration: .zero
        )
    }
}

private struct StubStreamingTranscriber: StreamingTranscriber {
    let capabilities = TranscriberCapabilities()

    func prepare() async throws {}

    func modelDownloadProgress() -> AsyncStream<ModelDownloadProgress> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }

    func transcribe(
        stream: AsyncThrowingStream<PCMBuffer, Error>
    ) -> AsyncThrowingStream<StreamingTranscriptionEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }
}

private struct StubSpeakerDiarizer: SpeakerDiarizer {
    func prepare() async throws {}

    func modelDownloadProgress() -> AsyncStream<ModelDownloadProgress> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }

    func diarize(
        stream: AsyncThrowingStream<PCMBuffer, Error>
    ) -> AsyncStream<SpeakerDiarizationEvent> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }
}

private final class MarkerTranscriber2: @unchecked Sendable, Transcriber2 {
    let capabilities = TranscriberCapabilities()

    func prepare() async throws {}

    func modelDownloadProgress() -> AsyncStream<ModelDownloadProgress> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }

    func transcribe(_ audio: PCMBuffer) async throws -> TranscriptionResult {
        TranscriptionResult(
            text: "marker",
            audioDuration: audio.duration,
            processingDuration: .zero
        )
    }
}

private final class MarkerStreamingTranscriber: @unchecked Sendable, StreamingTranscriber {
    let capabilities = TranscriberCapabilities()

    func prepare() async throws {}

    func modelDownloadProgress() -> AsyncStream<ModelDownloadProgress> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }

    func transcribe(
        stream: AsyncThrowingStream<PCMBuffer, Error>
    ) -> AsyncThrowingStream<StreamingTranscriptionEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }
}

private final class MarkerSpeakerDiarizer: @unchecked Sendable, SpeakerDiarizer {
    func prepare() async throws {}

    func modelDownloadProgress() -> AsyncStream<ModelDownloadProgress> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }

    func diarize(
        stream: AsyncThrowingStream<PCMBuffer, Error>
    ) -> AsyncStream<SpeakerDiarizationEvent> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }
}

private final class StubModelBoundProcessorProvider: @unchecked Sendable, ModelBoundProcessorProviding {
    private let isDownloadedValue: Bool
    private(set) var downloadedDescriptorIDs: [String] = []
    private(set) var removedDescriptorIDs: [String] = []

    init(isDownloadedValue: Bool = false) {
        self.isDownloadedValue = isDownloadedValue
    }

    func transcriber(for descriptor: ModelDescriptor) throws -> any Transcriber2 {
        StubTranscriber2()
    }

    func streamingTranscriber(for descriptor: ModelDescriptor) throws -> any StreamingTranscriber {
        StubStreamingTranscriber()
    }

    func diarizer(for descriptor: ModelDescriptor) throws -> any SpeakerDiarizer {
        StubSpeakerDiarizer()
    }

    func isDownloaded(_ descriptor: ModelDescriptor) -> Bool {
        isDownloadedValue
    }

    func download(
        _ descriptor: ModelDescriptor,
        progress: @escaping @Sendable (ModelDownloadProgress) -> Void
    ) async throws {
        downloadedDescriptorIDs.append(descriptor.id)
        progress(
            ModelDownloadProgress(
                phase: .finished,
                fractionCompleted: 1,
                receivedBytes: 0,
                expectedBytes: nil
            )
        )
    }

    func removeDownloadedFiles(_ descriptor: ModelDescriptor) throws {
        removedDescriptorIDs.append(descriptor.id)
    }
}

private struct TestStorageLocator: StorageLocator {
    let baseDirectory: URL

    static func make() -> TestStorageLocator {
        TestStorageLocator(
            baseDirectory: FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
        )
    }

    func url(for directory: ManagedDirectory) -> URL {
        baseDirectory
            .appendingPathComponent(directory.pathComponent, isDirectory: true)
            .standardizedFileURL
    }

    func ensureDirectoriesExist() throws {}
}

private final class AtomicIntBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: Int = 0

    func increment() {
        lock.lock()
        defer { lock.unlock() }
        _value += 1
    }

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return _value
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

private func makeMarkerDirectory(
    for descriptor: ModelDescriptor,
    storageLocator: any StorageLocator
) throws {
    let directory = modelDirectory(for: descriptor, storageLocator: storageLocator)
    let markerFile = directory.appendingPathComponent("marker.txt", isDirectory: false)
    try FileManager.default.createDirectory(
        at: directory,
        withIntermediateDirectories: true
    )
    try Data("marker".utf8).write(to: markerFile)
}
