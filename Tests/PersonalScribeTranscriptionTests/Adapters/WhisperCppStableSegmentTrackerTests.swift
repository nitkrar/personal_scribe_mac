import XCTest
@testable import PersonalScribeTranscription

final class WhisperCppStableSegmentTrackerTests: XCTestCase {
    func testSecondMatchingPassMovesStablePrefixOutOfPartialTail() {
        var tracker = WhisperCppStableSegmentTracker()

        _ = tracker.ingest([
            makeSegment("hello", 0, 300),
            makeSegment("world", 300, 600),
        ])

        XCTAssertEqual(tracker.currentUtteranceText, "hello world")
        XCTAssertEqual(tracker.pendingStableText, "")
        XCTAssertEqual(tracker.partialText, "hello world")

        _ = tracker.ingest([
            makeSegment("hello", 0, 300),
            makeSegment("world", 300, 600),
            makeSegment("again", 600, 900),
        ])

        XCTAssertEqual(tracker.currentUtteranceText, "hello world again")
        XCTAssertEqual(tracker.pendingStableText, "hello world")
        XCTAssertEqual(tracker.partialText, "again")
    }

    func testLeadingStablePrefixCarriesForwardWhenRollingWindowDropsIt() {
        var tracker = WhisperCppStableSegmentTracker()

        _ = tracker.ingest([
            makeSegment("hello", 0, 300),
            makeSegment("world", 300, 600),
        ])
        _ = tracker.ingest([
            makeSegment("hello", 0, 300),
            makeSegment("world", 300, 600),
        ])
        _ = tracker.ingest([
            makeSegment("world", 300, 600),
            makeSegment("again", 600, 900),
        ])

        XCTAssertEqual(tracker.currentUtteranceText, "hello world again")
        XCTAssertEqual(tracker.pendingStableText, "hello world")
        XCTAssertEqual(tracker.partialText, "again")
    }

    func testStablePrefixFlushReturnsNilUntilSegmentsConfirm() {
        var tracker = WhisperCppStableSegmentTracker()

        _ = tracker.ingest([
            makeSegment("hello", 0, 300),
        ])

        XCTAssertNil(tracker.flushStablePrefix())
        XCTAssertEqual(tracker.currentUtteranceText, "hello")
        XCTAssertEqual(tracker.pendingStableText, "")
        XCTAssertEqual(tracker.partialText, "hello")
        XCTAssertEqual(tracker.finalText, "hello")
    }

    func testStablePrefixFlushCommitsOnlyConfirmedPrefixAndStripsCommittedReplay() {
        var tracker = WhisperCppStableSegmentTracker()

        _ = tracker.ingest([
            makeSegment("hello", 0, 300),
            makeSegment("world", 300, 600),
        ])
        _ = tracker.ingest([
            makeSegment("hello", 0, 300),
            makeSegment("world", 300, 600),
            makeSegment("again", 600, 900),
        ])

        XCTAssertEqual(tracker.flushStablePrefix(), "hello world")
        XCTAssertEqual(tracker.currentUtteranceText, "again")
        XCTAssertEqual(tracker.pendingStableText, "")
        XCTAssertEqual(tracker.partialText, "again")
        XCTAssertEqual(tracker.finalText, "hello world again")

        _ = tracker.ingest([
            makeSegment("world", 300, 600),
            makeSegment("again", 600, 900),
        ])

        XCTAssertEqual(tracker.currentUtteranceText, "again")
        XCTAssertEqual(tracker.pendingStableText, "again")
        XCTAssertEqual(tracker.partialText, "")
        XCTAssertEqual(tracker.finalText, "hello world again")
    }

    func testCommittedReplayRegroupedIntoSingleSegmentDoesNotBecomeNewBoundaryText() {
        var tracker = WhisperCppStableSegmentTracker()

        _ = tracker.ingest([
            makeSegment("Let's see.", 0, 300),
            makeSegment("This is odd.", 300, 600),
        ])
        _ = tracker.ingest([
            makeSegment("Let's see.", 0, 300),
            makeSegment("This is odd.", 300, 600),
        ])

        XCTAssertEqual(tracker.flushStablePrefix(), "Let's see. This is odd.")
        XCTAssertEqual(tracker.currentUtteranceText, "")
        XCTAssertEqual(tracker.finalText, "Let's see. This is odd.")

        _ = tracker.ingest([
            makeSegment("let's see this is odd", 0, 600),
            makeSegment("again", 600, 900),
        ])

        XCTAssertEqual(tracker.currentUtteranceText, "again")
        XCTAssertEqual(tracker.pendingStableText, "")
        XCTAssertEqual(tracker.partialText, "again")

        _ = tracker.ingest([
            makeSegment("let's see this is odd", 0, 600),
            makeSegment("again", 600, 900),
        ])

        XCTAssertEqual(tracker.flushStablePrefix(), "again")
        XCTAssertEqual(tracker.currentUtteranceText, "")
        XCTAssertEqual(tracker.finalText, "Let's see. This is odd. again")
    }
}

private extension WhisperCppStableSegmentTrackerTests {
    func makeSegment(
        _ text: String,
        _ startMs: Int64,
        _ endMs: Int64
    ) -> WhisperCppDecodedSegment {
        WhisperCppDecodedSegment(text: text, startMs: startMs, endMs: endMs)
    }
}
