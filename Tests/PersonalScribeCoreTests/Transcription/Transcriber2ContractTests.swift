import XCTest
@testable import PersonalScribeCore

/// #078.4 — `Transcriber2` is the new batch ASR protocol. Tests pin
/// composition with `ModelLifecycle` (L13), the `capabilities`
/// accessor (L11), and the batch `transcribe(_:)` signature.
final class Transcriber2ContractTests: XCTestCase {

    // MARK: - Test fixtures

    private struct StubTranscriber: Transcriber2 {
        let capabilities: TranscriberCapabilities
        let pinnedResult: TranscriptionResult

        func prepare() async throws { /* no-op */ }

        func modelDownloadProgress() -> AsyncStream<ModelDownloadProgress> {
            AsyncStream { continuation in
                continuation.finish()
            }
        }

        func transcribe(_ audio: PCMBuffer) async throws -> TranscriptionResult {
            pinnedResult
        }
    }

    private func makeBuffer() throws -> PCMBuffer {
        try PCMBuffer(
            samples: Array(repeating: 0, count: 16_000),
            timestamp: ContinuousClock().now
        )
    }

    // MARK: - Tests

    func testTranscriber2ComposesModelLifecycle() async throws {
        // A `Transcriber2` value must also be usable through the
        // `ModelLifecycle` existential. If composition is dropped,
        // the upcast fails to compile (oracle for L13).
        let stub = StubTranscriber(
            capabilities: TranscriberCapabilities(),
            pinnedResult: TranscriptionResult(
                text: "",
                audioDuration: .zero,
                processingDuration: .zero
            )
        )

        let lifecycle: any ModelLifecycle = stub
        try await lifecycle.prepare()

        // modelDownloadProgress() callable through the lifecycle
        // existential — closes the loop on the composition contract.
        var emitted = 0
        for await _ in lifecycle.modelDownloadProgress() {
            emitted += 1
        }
        XCTAssertEqual(emitted, 0, "Stub finishes the stream immediately")
    }

    func testTranscriber2RequiresCapabilities() {
        // The protocol mandates a `capabilities` accessor (L11). The
        // stub must surface the value the test injected.
        let parakeetLike = TranscriberCapabilities(
            providesTokenTimings: true,
            providesConfidence: true,
            providesPerformanceMetrics: true,
            providesCustomVocabulary: true
        )
        let stub = StubTranscriber(
            capabilities: parakeetLike,
            pinnedResult: TranscriptionResult(
                text: "",
                audioDuration: .zero,
                processingDuration: .zero
            )
        )

        XCTAssertEqual(stub.capabilities, parakeetLike)
    }

    func testTranscriber2TranscribeReturnsTranscriptionResult() async throws {
        // Batch `transcribe(_:)` returns `TranscriptionResult`. The
        // pinned value flows through the protocol method.
        let pinned = TranscriptionResult(
            text: "hello",
            audioDuration: .seconds(1),
            processingDuration: .milliseconds(50),
            confidence: 0.91
        )
        let stub = StubTranscriber(
            capabilities: TranscriberCapabilities(providesConfidence: true),
            pinnedResult: pinned
        )

        let buffer = try makeBuffer()
        let result = try await stub.transcribe(buffer)

        XCTAssertEqual(result.text, "hello")
        XCTAssertEqual(result.confidence, 0.91)
        XCTAssertEqual(result.audioDuration, .seconds(1))
    }
}
