import XCTest
import PersonalScribeCore
import PersonalScribeSession
@testable import PersonalScribeAppKit

/// The pipeline's output stage: delivery is the recipe's last step, run
/// by the orchestrator (not by UI code watching state changes).
@MainActor
final class SessionOutputStageTests: XCTestCase {
    func testFinalDeliveryEndsLiveSessionThenDeliversTranscriptToRecipeSinks() async throws {
        let events = EventLog()
        let batch = FakeBatchOutput(events: events, result: .delivered(target: .frontmostApp, delivery: .paste))
        let stage = SessionOutputStage(
            live: FakeLiveOutput(events: events),
            batch: batch,
            logger: PersonalScribeLogger.testing(category: PersonalScribeLogCategory.ui)
        )
        let sinks: [BoundOutputSink] = [.clipboard(restoreEnabled: true), .frontmostPaste(enabled: true)]

        try await stage.deliverFinal(
            TranscriptionResult(text: "final words", audioDuration: .seconds(1), processingDuration: .zero),
            sinks: sinks
        )

        // Live cursor restores the clipboard on session end; the batch
        // paste must come after, or the restore would clobber it.
        XCTAssertEqual(events.entries, ["live.endSession", "batch.deliver"])
        XCTAssertEqual(batch.deliveredTexts, ["final words"])
        XCTAssertEqual(batch.deliveredSinks, [sinks])
    }

    func testClipboardOnlyDeliveryRaisesNotice() async throws {
        let events = EventLog()
        let stage = SessionOutputStage(
            live: FakeLiveOutput(events: events),
            batch: FakeBatchOutput(events: events, result: .delivered(target: .clipboardOnly, delivery: .clipboardOnly)),
            logger: PersonalScribeLogger.testing(category: PersonalScribeLogCategory.ui)
        )
        var notices: [ClipboardNotice] = []
        stage.onClipboardOnlyCopy = { notices.append($0) }

        try await stage.deliverFinal(
            TranscriptionResult(text: "copied", audioDuration: .seconds(1), processingDuration: .zero),
            sinks: [.clipboard(restoreEnabled: false)]
        )

        XCTAssertEqual(notices, [.copied])
    }

    /// No Accessibility: paste is skipped, nothing blocks, and the notice
    /// says why so the user knows how to get auto-paste back.
    func testClipboardDeliveryWithoutAccessibilityRaisesAccessibilityNotice() async throws {
        let events = EventLog()
        let stage = SessionOutputStage(
            live: FakeLiveOutput(events: events),
            batch: FakeBatchOutput(
                events: events,
                result: .delivered(target: .clipboardNeedsAccessibility, delivery: .clipboardOnly)
            ),
            logger: PersonalScribeLogger.testing(category: PersonalScribeLogCategory.ui)
        )
        var notices: [ClipboardNotice] = []
        stage.onClipboardOnlyCopy = { notices.append($0) }

        try await stage.deliverFinal(
            TranscriptionResult(text: "copied", audioDuration: .seconds(1), processingDuration: .zero),
            sinks: [.clipboard(restoreEnabled: false)]
        )

        XCTAssertEqual(notices, [.needsAccessibility])
    }
}

@MainActor
private final class EventLog {
    var entries: [String] = []
}

private final class FakeLiveOutput: PipelineOutputSink, @unchecked Sendable {
    private let events: EventLog
    init(events: EventLog) { self.events = events }
    func deliverPartial(_ revision: TranscriptProgress) async throws {}
    func deliverFinal(_ result: TranscriptionResult, sinks: [BoundOutputSink]) async throws {}
    func resetForNewSession() async {}
    func endSession() async {
        await MainActor.run { events.entries.append("live.endSession") }
    }
}

@MainActor
private final class FakeBatchOutput: OutputService, @unchecked Sendable {
    private let events: EventLog
    private let result: OutputResult
    private(set) var deliveredTexts: [String] = []
    private(set) var deliveredSinks: [[BoundOutputSink]] = []

    init(events: EventLog, result: OutputResult) {
        self.events = events
        self.result = result
    }

    func deliverBatch(text: String, sinks: [BoundOutputSink]) async -> OutputResult {
        events.entries.append("batch.deliver")
        deliveredTexts.append(text)
        deliveredSinks.append(sinks)
        return result
    }
}
