import XCTest
@testable import PersonalScribeCore

/// #078.5 — `StreamingTranscriber` is the streaming ASR surface.
/// Tests pin the event-case set (partial / endOfUtterance / finalized)
/// and that the protocol composes `ModelLifecycle` per L13.
final class StreamingTranscriberContractTests: XCTestCase {

    // MARK: - Test fixtures

    private struct StubStreaming: StreamingTranscriber {
        let capabilities: TranscriberCapabilities

        func prepare() async throws { /* no-op */ }

        func modelDownloadProgress() -> AsyncStream<ModelDownloadProgress> {
            AsyncStream { continuation in
                continuation.finish()
            }
        }

        func releaseIdleResources() async {}

        func transcribe(
            stream: AsyncThrowingStream<PCMBuffer, Error>
        ) -> AsyncThrowingStream<StreamingTranscriptionEvent, Error> {
            AsyncThrowingStream { continuation in
                continuation.finish()
            }
        }
    }

    // MARK: - Tests

    func testStreamingEventCasesAreExhaustive() {
        // Pin the three cases by exhaustive switch. If a future
        // change adds a fourth case, the switch becomes non-
        // exhaustive and the test fails to compile — the load-
        // bearing oracle for "case set is exactly three."
        let cases: [StreamingTranscriptionEvent] = [
            .partial(text: "p"),
            .endOfUtterance(text: "e"),
            .finalized(
                TranscriptionResult(
                    text: "f",
                    audioDuration: .zero,
                    processingDuration: .zero
                )
            ),
        ]

        var seenPartial = false
        var seenEOU = false
        var seenFinal = false

        for event in cases {
            switch event {
            case .partial(let text):
                seenPartial = true
                XCTAssertEqual(text, "p")
            case .endOfUtterance(let text):
                seenEOU = true
                XCTAssertEqual(text, "e")
            case .finalized(let result):
                seenFinal = true
                XCTAssertEqual(result.text, "f")
            }
        }

        XCTAssertTrue(seenPartial)
        XCTAssertTrue(seenEOU)
        XCTAssertTrue(seenFinal)
    }

    func testStreamingTranscriberComposesModelLifecycle() async throws {
        // A `StreamingTranscriber` must also be usable through
        // the `ModelLifecycle` existential — composition contract
        // per L13.
        let stub = StubStreaming(capabilities: TranscriberCapabilities())
        let lifecycle: any ModelLifecycle = stub
        try await lifecycle.prepare()
        var emitted = 0
        for await _ in lifecycle.modelDownloadProgress() {
            emitted += 1
        }
        XCTAssertEqual(emitted, 0)
    }
}
