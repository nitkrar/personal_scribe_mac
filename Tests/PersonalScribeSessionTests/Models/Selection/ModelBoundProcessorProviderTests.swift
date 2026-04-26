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

        var emitted: [ModelDownloadProgress.Phase] = []
        try await provider.download(descriptor) { progress in
            emitted.append(progress.phase)
        }
        try provider.removeDownloadedFiles(descriptor)

        XCTAssertEqual(emitted, [.finished])
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
