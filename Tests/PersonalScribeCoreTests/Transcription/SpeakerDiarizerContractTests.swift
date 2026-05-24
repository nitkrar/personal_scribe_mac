import XCTest
@testable import PersonalScribeCore

/// #078.6 — `SpeakerDiarizer` is the diarization surface composing
/// `ModelLifecycle`. Tests pin: `SpeakerTurn` field set, `.update`
/// event carries provisional + finalized separately (L10), and the
/// batch convenience `diarize(_:)` wraps a one-buffer stream.
final class SpeakerDiarizerContractTests: XCTestCase {

    // MARK: - Test fixtures

    private struct StubDiarizer: SpeakerDiarizer {
        let pinnedEvents: [SpeakerDiarizationEvent]

        func prepare() async throws { /* no-op */ }

        func modelDownloadProgress() -> AsyncStream<ModelDownloadProgress> {
            AsyncStream { continuation in
                continuation.finish()
            }
        }

        func releaseIdleResources() async {}

        func diarize(
            stream: AsyncThrowingStream<PCMBuffer, Error>
        ) -> AsyncStream<SpeakerDiarizationEvent> {
            // Drain the input stream concurrently so the input is
            // consumed (mirrors the contract a real adapter would
            // implement — pulled chunks travel into the manager).
            // Then emit the pinned events in order.
            let events = pinnedEvents
            return AsyncStream { continuation in
                let drainTask = Task {
                    do {
                        for try await _ in stream { /* drop */ }
                    } catch { /* drop */ }
                }
                Task {
                    _ = await drainTask.value
                    for event in events {
                        continuation.yield(event)
                    }
                    continuation.finish()
                }
            }
        }
    }

    private func makeBuffer() throws -> PCMBuffer {
        try PCMBuffer(
            samples: Array(repeating: 0, count: 16_000),
            timestamp: ContinuousClock().now
        )
    }

    // MARK: - Tests

    func testSpeakerTurnPreservesIDAndDurations() {
        let turn = SpeakerTurn(
            speakerID: "speaker_1",
            start: .seconds(2),
            end: .seconds(5)
        )

        XCTAssertEqual(turn.speakerID, "speaker_1")
        XCTAssertEqual(turn.start, .seconds(2))
        XCTAssertEqual(turn.end, .seconds(5))
    }

    func testDiarizationEventCarriesProvisionalAndFinalizedSeparately() {
        // L10 / L26: `.update` MUST hold provisional and finalized
        // as distinct lists so the fusion processor can ignore
        // provisional turns (no ASR until finalize).
        let provisional = [
            SpeakerTurn(
                speakerID: "speaker_0",
                start: .seconds(0),
                end: .seconds(2)
            )
        ]
        let finalized = [
            SpeakerTurn(
                speakerID: "speaker_1",
                start: .seconds(3),
                end: .seconds(7)
            )
        ]

        let event: SpeakerDiarizationEvent = .update(
            provisional: provisional,
            finalized: finalized
        )

        switch event {
        case .update(let p, let f):
            XCTAssertEqual(p, provisional)
            XCTAssertEqual(f, finalized)
            XCTAssertNotEqual(p, f, "Provisional and finalized must be distinct lists")
        case .terminal, .failed(reason: _):
            XCTFail("Expected .update case")
        }
    }

    func testBatchConvenienceWrapsSingleBufferStream() async throws {
        // The protocol extension `diarize(_:)` should accept a
        // single buffer and return a stream that produces the same
        // events the streaming entry point would. Pin one terminal
        // event with one turn and assert it survives the wrap.
        let pinned: [SpeakerDiarizationEvent] = [
            .terminal([
                SpeakerTurn(
                    speakerID: "speaker_0",
                    start: .seconds(0),
                    end: .seconds(1)
                )
            ])
        ]
        let stub = StubDiarizer(pinnedEvents: pinned)
        let buffer = try makeBuffer()

        var collected: [SpeakerDiarizationEvent] = []
        for await event in stub.diarize(buffer) {
            collected.append(event)
        }

        XCTAssertEqual(collected, pinned)
    }

    func testDiarizationEventCarriesFailureReason() {
        let event: SpeakerDiarizationEvent = .failed(reason: "boom")

        switch event {
        case .failed(let reason):
            XCTAssertEqual(reason, "boom")
        case .update, .terminal:
            XCTFail("Expected .failed case")
        }
    }
}
