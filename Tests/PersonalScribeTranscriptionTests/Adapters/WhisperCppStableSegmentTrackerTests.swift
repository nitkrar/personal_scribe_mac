import XCTest
@testable import PersonalScribeTranscription

final class WhisperCppStableSegmentTrackerTests: XCTestCase {
    func testIngestStartsFreshWithUnconfirmedSegments() {
        var tracker = WhisperCppStableSegmentTracker()

        _ = tracker.ingest([
            makeSegment("hello", 0, 300),
            makeSegment("world", 300, 600),
        ])

        XCTAssertEqual(tracker.currentUtteranceText, "hello world")
        XCTAssertEqual(tracker.partialText, "hello world")
        XCTAssertEqual(tracker.finalText, "hello world")
        XCTAssertNil(tracker.flushStablePrefix())
    }

    func testRepeatedIngestionConfirmsSegmentAfterThresholdMatches() {
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

        XCTAssertEqual(tracker.currentUtteranceText, "hello world again")
        XCTAssertEqual(tracker.partialText, "again")
        XCTAssertEqual(tracker.flushStablePrefix(), "hello world")
        XCTAssertEqual(tracker.currentUtteranceText, "again")
    }

    func testFlushStablePrefixDrainsConfirmedSegmentsAndReturnsJoinedText() {
        var tracker = WhisperCppStableSegmentTracker()

        _ = tracker.ingest([
            makeSegment("hello", 0, 300),
            makeSegment("world", 300, 600),
        ])
        _ = tracker.ingest([
            makeSegment("hello", 0, 300),
            makeSegment("world", 300, 600),
        ])

        XCTAssertEqual(tracker.flushStablePrefix(), "hello world")
        XCTAssertEqual(tracker.currentUtteranceText, "")
        XCTAssertEqual(tracker.partialText, "")
        XCTAssertEqual(tracker.finalText, "hello world")
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
        XCTAssertEqual(tracker.partialText, "again")
        XCTAssertEqual(tracker.finalText, "hello world again")

        _ = tracker.ingest([
            makeSegment("world", 300, 600),
            makeSegment("again", 600, 900),
        ])

        XCTAssertEqual(tracker.currentUtteranceText, "again")
        XCTAssertEqual(tracker.partialText, "")
        XCTAssertEqual(tracker.finalText, "hello world again")
    }

    func testNormalizedTextMatchIgnoresWhitespaceAndCase() {
        var tracker = WhisperCppStableSegmentTracker()

        _ = tracker.ingest([
            makeSegment(" Hello   WORLD ", 0, 300),
        ])
        _ = tracker.ingest([
            makeSegment("hello world", 0, 300),
        ])

        XCTAssertEqual(tracker.flushStablePrefix(), "hello world")
        XCTAssertEqual(tracker.finalText, "hello world")
    }

    func testTimestampDriftWithinToleranceCountsAsMatch() {
        var tracker = WhisperCppStableSegmentTracker()

        _ = tracker.ingest([
            makeSegment("hello", 0, 300),
        ])
        _ = tracker.ingest([
            makeSegment("hello", 280, 620),
        ])

        XCTAssertEqual(tracker.flushStablePrefix(), "hello")
        XCTAssertEqual(tracker.finalText, "hello")
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
        XCTAssertEqual(tracker.partialText, "again")

        _ = tracker.ingest([
            makeSegment("let's see this is odd", 0, 600),
            makeSegment("again", 600, 900),
        ])

        XCTAssertEqual(tracker.flushStablePrefix(), "again")
        XCTAssertEqual(tracker.finalText, "Let's see. This is odd. again")
    }

    func testRegroupedCommittedReplayDoesNotReappearInPartialOrBoundary() {
        var tracker = WhisperCppStableSegmentTracker()

        _ = tracker.ingest([
            makeSegment("hello", 0, 300),
            makeSegment("world", 300, 600),
        ])
        _ = tracker.ingest([
            makeSegment("hello", 0, 300),
            makeSegment("world", 300, 600),
        ])

        XCTAssertEqual(tracker.flushStablePrefix(), "hello world")

        _ = tracker.ingest([
            makeSegment("hello world", 0, 600),
            makeSegment("again", 600, 900),
        ])

        XCTAssertEqual(tracker.currentUtteranceText, "again")
        XCTAssertEqual(tracker.partialText, "again")

        _ = tracker.ingest([
            makeSegment("hello world", 0, 600),
            makeSegment("again", 600, 900),
        ])

        XCTAssertEqual(tracker.flushStablePrefix(), "again")
        XCTAssertEqual(tracker.currentUtteranceText, "")
        XCTAssertEqual(tracker.partialText, "")
        XCTAssertEqual(tracker.finalText, "hello world again")
    }

    func testCommittedPrefixMergedIntoSingleIncomingSegmentDedupsToTailOnly() {
        var tracker = WhisperCppStableSegmentTracker()

        _ = tracker.ingest([
            makeSegment("hello world", 0, 600),
        ])
        _ = tracker.ingest([
            makeSegment("hello world", 0, 600),
        ])

        XCTAssertEqual(tracker.flushStablePrefix(), "hello world")

        _ = tracker.ingest([
            makeSegment("hello world again", 0, 1200),
        ])
        _ = tracker.ingest([
            makeSegment("hello world again", 0, 1200),
        ])

        XCTAssertEqual(tracker.flushStablePrefix(), "again")
        XCTAssertEqual(tracker.finalText, "hello world again")
    }

    func testCommittedPrefixWithEmptyTailDropsIncomingEntirely() {
        var tracker = WhisperCppStableSegmentTracker()

        _ = tracker.ingest([
            makeSegment("hello world", 0, 600),
        ])
        _ = tracker.ingest([
            makeSegment("hello world", 0, 600),
        ])

        XCTAssertEqual(tracker.flushStablePrefix(), "hello world")

        _ = tracker.ingest([
            makeSegment("hello world", 0, 600),
        ])
        _ = tracker.ingest([
            makeSegment("hello world", 0, 600),
        ])

        XCTAssertNil(tracker.flushStablePrefix())
        XCTAssertEqual(tracker.finalText, "hello world")
    }

    func testGenuinelyDifferentRedecodeDoesNotDedup() {
        var tracker = WhisperCppStableSegmentTracker()

        _ = tracker.ingest([
            makeSegment("hello world", 0, 600),
        ])
        _ = tracker.ingest([
            makeSegment("hello world", 0, 600),
        ])

        XCTAssertEqual(tracker.flushStablePrefix(), "hello world")

        _ = tracker.ingest([
            makeSegment("hello whirled again", 0, 1200),
        ])
        _ = tracker.ingest([
            makeSegment("hello whirled again", 0, 1200),
        ])

        XCTAssertEqual(tracker.flushStablePrefix(), "hello whirled again")
        XCTAssertEqual(tracker.finalText, "hello world hello whirled again")
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
