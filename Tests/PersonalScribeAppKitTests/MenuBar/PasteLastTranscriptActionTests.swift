import Foundation
import XCTest
import PersonalScribeCore
@testable import PersonalScribeAppKit

/// Tests for `PasteLastTranscriptAction` — the menu-bar "Paste Last
/// Transcript" handler. Validates that the action reads the single
/// most-recent transcript from `TranscriptReading` and forwards the
/// entry's text through the shared `OutputService` pipeline, and
/// no-ops silently when history is empty.
@MainActor
final class PasteLastTranscriptActionTests: XCTestCase {
    // MARK: - Fixtures

    private func makeEntry(
        id: UUID = UUID(),
        text: String,
        timestamp: Date = Date(timeIntervalSince1970: 1_700_000_000),
        audioDuration: TimeInterval = 3.0,
        processingDuration: TimeInterval = 0.5
    ) -> TranscriptEntry {
        TranscriptEntry(
            id: id,
            timestamp: timestamp,
            text: text,
            audioDuration: audioDuration,
            processingDuration: processingDuration
        )
    }

    // MARK: - Tests

    /// `perform()` must call `TranscriptReading.recent(limit:)` with a
    /// limit of exactly 1 — we only paste the single latest entry.
    func testPerformCallsReaderWithLimitOne() async {
        let reader = FakeTranscriptReader()
        await reader.seed(recent: [makeEntry(text: "anything")])
        let output = FakeOutputService()
        let action = PasteLastTranscriptAction(
            transcriptReader: reader,
            outputService: output
        )

        _ = await action.perform()

        let callCount = await reader.recentCallCount
        let lastLimit = await reader.lastRecentLimit
        XCTAssertEqual(callCount, 1)
        XCTAssertEqual(lastLimit, 1)
    }

    /// Happy path: with one entry in history, `perform()` delivers the
    /// entry's `text` through the output pipeline and returns a
    /// non-nil `OutputResult`.
    func testPerformDeliversMostRecentEntryText() async {
        let reader = FakeTranscriptReader()
        await reader.seed(recent: [makeEntry(text: "hello world")])
        let output = FakeOutputService()
        let action = PasteLastTranscriptAction(
            transcriptReader: reader,
            outputService: output
        )

        let result = await action.perform()

        XCTAssertNotNil(result)
        XCTAssertEqual(output.deliverCallCount, 1)
        XCTAssertEqual(output.lastBatchText, "hello world")
    }

    /// Empty history: `perform()` returns `nil` and never touches the
    /// output service — silent no-op by design (future milestones may
    /// surface a "nothing to paste yet" notice).
    func testPerformReturnsNilAndDoesNotDeliverWhenHistoryIsEmpty() async {
        let reader = FakeTranscriptReader()
        await reader.seed(recent: [])
        let output = FakeOutputService()
        let action = PasteLastTranscriptAction(
            transcriptReader: reader,
            outputService: output
        )

        let result = await action.perform()

        XCTAssertNil(result)
        XCTAssertEqual(output.deliverCallCount, 0)
        XCTAssertNil(output.lastBatchText)
    }

    /// Defensive: even if the reader returns more than one entry
    /// (shouldn't happen for `limit: 1`, but `TranscriptReading` does
    /// not contractually forbid it), we deliver only the first.
    func testPerformDeliversOnlyFirstEntryWhenReaderReturnsMultiple() async {
        let reader = FakeTranscriptReader()
        await reader.seed(recent: [
            makeEntry(text: "newest"),
            makeEntry(text: "older"),
            makeEntry(text: "oldest")
        ])
        let output = FakeOutputService()
        let action = PasteLastTranscriptAction(
            transcriptReader: reader,
            outputService: output
        )

        let result = await action.perform()

        XCTAssertNotNil(result)
        XCTAssertEqual(output.deliverCallCount, 1)
        XCTAssertEqual(output.lastBatchText, "newest")
    }
}

// MARK: - Inline fakes

/// `TranscriptReading` fake. Modeled as an `actor` to match the
/// existing precedent (`InlineFakeTranscriptReader` in
/// `TranscriptionsTabViewModelTests`) and to satisfy the protocol's
/// non-isolated async requirements cleanly under Swift 6 strict
/// concurrency — no `@unchecked Sendable` escape hatch needed for
/// the reader.
private actor FakeTranscriptReader: TranscriptReading {
    private var recentResult: [TranscriptEntry] = []
    private var searchResult: [TranscriptEntry] = []
    private var allResult: [TranscriptEntry] = []
    private(set) var recentCallCount = 0
    private(set) var lastRecentLimit: Int?

    func seed(
        recent: [TranscriptEntry] = [],
        search: [TranscriptEntry] = [],
        all: [TranscriptEntry] = []
    ) {
        recentResult = recent
        searchResult = search
        allResult = all
    }

    func recent(limit: Int) async -> [TranscriptEntry] {
        recentCallCount += 1
        lastRecentLimit = limit
        return recentResult
    }

    func search(query: String) async -> [TranscriptEntry] { searchResult }

    func all() async -> [TranscriptEntry] { allResult }
}

/// `OutputService` fake. `OutputService` is declared `@MainActor`, so
/// the conformance must live on MainActor; the class is `final` and
/// marked `@unchecked Sendable` to cross actor boundaries safely
/// (mirrors the real `ClipboardBatchOutput`). All state access is
/// MainActor-isolated.
@MainActor
private final class FakeOutputService: OutputService, @unchecked Sendable {
    var lastBatchText: String?
    var deliverCallCount = 0
    var stubResult: OutputResult = .delivered(
        target: .clipboardOnly,
        delivery: .clipboardOnly
    )

    func deliverBatch(text: String) async -> OutputResult {
        deliverCallCount += 1
        lastBatchText = text
        return stubResult
    }
}
