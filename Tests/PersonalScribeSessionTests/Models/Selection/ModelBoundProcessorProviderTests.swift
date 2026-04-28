import Foundation
import XCTest
@testable import PersonalScribeCore
@testable import PersonalScribeSession

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
                    transcriber: MarkerTranscriber()
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
                    transcriber: MarkerTranscriber()
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
                        transcriber: MarkerTranscriber()
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
                        transcriber: MarkerTranscriber()
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

    /// Hybrid descriptors (110m TDT-CTC) declare an auxiliary repo
    /// (`parakeet-ctc-110m-coreml`) whose folder lives next to the
    /// primary leaf. `removeDownloadedFiles` must wipe both — otherwise
    /// the user "deletes the model" but ~98MB of CTC head bytes
    /// orphan on disk.
    func testRemoveDownloadedFilesAlsoRemovesAuxiliaryRepoFolders() throws {
        let storageLocator = TestStorageLocator.make()
        let descriptor = BuiltInModelCatalog.parakeetTDTCTC110M
        XCTAssertEqual(
            descriptor.auxiliaryRepoFolderNames,
            ["parakeet-ctc-110m-coreml"],
            "Catalog precondition: 110m hybrid declares its CTC head as auxiliary"
        )
        let provider = ModelBoundProcessorProvider(
            storageLocator: storageLocator,
            adapterFactory: { d in
                AdapterRecord(
                    descriptorID: d.id,
                    transcriber: MarkerTranscriber()
                )
            }
        )

        // Seed both leaves on disk.
        let primaryLeaf = modelDirectory(for: descriptor, storageLocator: storageLocator)
        let auxLeaf = storageLocator
            .url(for: .models)
            .appendingPathComponent("parakeet-ctc-110m-coreml", isDirectory: true)
            .standardizedFileURL
        try FileManager.default.createDirectory(at: primaryLeaf, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: auxLeaf, withIntermediateDirectories: true)
        try Data("marker".utf8).write(to: primaryLeaf.appendingPathComponent("marker.txt"))
        try Data("aux-marker".utf8).write(to: auxLeaf.appendingPathComponent("marker.txt"))

        try provider.removeDownloadedFiles(descriptor)

        XCTAssertFalse(
            FileManager.default.fileExists(atPath: primaryLeaf.path),
            "Primary 110m leaf must be removed"
        )
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: auxLeaf.path),
            "Auxiliary CTC head leaf must be removed"
        )
    }

    /// Regression guard for the AI Models tab: Qwen download state must
    /// treat FluidAudio's current 2-model layout as "downloaded", or the
    /// Settings row regresses to "Not downloaded" after app relaunch.
    func testIsDownloadedReturnsTrueForQwenWhenFluidAudioTwoModelLayoutExists() throws {
        let storageLocator = TestStorageLocator.make()
        let descriptor = BuiltInModelCatalog.qwen3AsrF32
        let provider = ModelBoundProcessorProvider(
            storageLocator: storageLocator,
            adapterFactory: { d in
                AdapterRecord(
                    descriptorID: d.id,
                    transcriber: MarkerTranscriber()
                )
            }
        )

        try seedQwenTwoModelLayout(
            for: descriptor,
            storageLocator: storageLocator
        )

        XCTAssertTrue(
            provider.isDownloaded(descriptor),
            "FluidAudio's Qwen layout should be treated as downloaded"
        )
    }
}

private final class MarkerTranscriber: @unchecked Sendable, Transcriber {
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

private func seedQwenTwoModelLayout(
    for descriptor: ModelDescriptor,
    storageLocator: any StorageLocator
) throws {
    let directory = modelDirectory(for: descriptor, storageLocator: storageLocator)
    let fileManager = FileManager.default
    let requiredRelativePaths = [
        "qwen3_asr_audio_encoder_v2.mlmodelc/coremldata.bin",
        "qwen3_asr_decoder_stateful.mlmodelc/coremldata.bin",
        "qwen3_asr_embeddings.bin",
        "vocab.json",
    ]

    for relativePath in requiredRelativePaths {
        let path = directory.appendingPathComponent(relativePath, isDirectory: false)
        try fileManager.createDirectory(
            at: path.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data: Data
        switch relativePath {
        case "vocab.json":
            data = Data("{\"hello\":0}".utf8)
        default:
            data = Data("artifact".utf8)
        }
        try data.write(to: path)
    }
}
