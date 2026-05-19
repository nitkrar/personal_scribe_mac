import Foundation
import XCTest
import PersonalScribeCore
@testable import PersonalScribeAppKit

/// Tests for `CopyLastTranscriptAction` — the menu-bar "Copy Last
/// Transcript" handler. Validates the strict clipboard-only contract:
/// read the single most-recent transcript, write it to the injected
/// clipboard writer, and report the outcome via `onCompleted`.
@MainActor
final class CopyLastTranscriptActionTests: XCTestCase {
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

    func testPerformWritesMostRecentTranscriptToClipboard() async {
        let reader = FakeTranscriptReader()
        await reader.seed(recent: [makeEntry(text: "hello")])
        let clipboardWriter = ClipboardWriterSpy()
        var outcomes: [CopyLastTranscriptOutcome] = []
        let action = CopyLastTranscriptAction(
            transcriptReader: reader,
            clipboardWriter: clipboardWriter.write(_:),
            onCompleted: { outcome in
                outcomes.append(outcome)
            }
        )

        await action.perform()

        XCTAssertEqual(clipboardWriter.writes, ["hello"])
        XCTAssertEqual(outcomes, [.copied(text: "hello")])
    }

    func testPerformEmptyHistoryReportsEmptyOutcomeAndDoesNotWriteClipboard() async {
        let reader = FakeTranscriptReader()
        await reader.seed(recent: [])
        let clipboardWriter = ClipboardWriterSpy()
        var outcomes: [CopyLastTranscriptOutcome] = []
        let action = CopyLastTranscriptAction(
            transcriptReader: reader,
            clipboardWriter: clipboardWriter.write(_:),
            onCompleted: { outcome in
                outcomes.append(outcome)
            }
        )

        await action.perform()

        XCTAssertTrue(clipboardWriter.writes.isEmpty)
        XCTAssertEqual(outcomes, [.emptyHistory])
    }

    func testPerformWritesOnlyTheMostRecentWhenHistoryHasMany() async {
        let reader = FakeTranscriptReader()
        await reader.seed(recent: [
            makeEntry(text: "newest"),
            makeEntry(text: "older"),
            makeEntry(text: "oldest")
        ])
        let clipboardWriter = ClipboardWriterSpy()
        let action = CopyLastTranscriptAction(
            transcriptReader: reader,
            clipboardWriter: clipboardWriter.write(_:),
            onCompleted: { _ in }
        )

        await action.perform()

        let callCount = await reader.recentCallCount
        let lastLimit = await reader.lastRecentLimit
        XCTAssertEqual(callCount, 1)
        XCTAssertEqual(lastLimit, 1)
        XCTAssertEqual(clipboardWriter.writes, ["newest"])
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

    func mostRecentEntryWithAudio() async -> TranscriptEntry? {
        allResult.first(where: { $0.audioFilename != nil })
    }
}

@MainActor
private final class ClipboardWriterSpy: @unchecked Sendable {
    private(set) var writes: [String] = []

    func write(_ text: String) {
        writes.append(text)
    }
}
