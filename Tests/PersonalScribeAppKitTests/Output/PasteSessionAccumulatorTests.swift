import XCTest
@testable import PersonalScribeAppKit

final class PasteSessionAccumulatorTests: XCTestCase {
    private final class MutableNowBox: @unchecked Sendable {
        var value: Date

        init(_ value: Date) {
            self.value = value
        }
    }

    func testRecordingLiveAttemptIncrementsAttemptCount() {
        var accumulator = PasteSessionAccumulator()

        accumulator.recordLiveAttempt(chars: 5)

        let summary = accumulator.summary(sink: .live, sessionID: "session-1")
        XCTAssertEqual(summary.livePasteAttempts, 1)
    }

    func testRecordingLiveSucceededIncrementsBothCountsAndChars() {
        var accumulator = PasteSessionAccumulator()

        accumulator.recordLiveSucceeded(chars: 7)

        let summary = accumulator.summary(sink: .live, sessionID: "session-1")
        XCTAssertEqual(summary.livePasteSucceeded, 1)
        XCTAssertEqual(summary.livePasteCumulativeCharsWritten, 7)
    }

    func testRecordingLiveFailedIncrementsFailedAndStoresReason() {
        var accumulator = PasteSessionAccumulator()

        accumulator.recordLiveFailed(reason: .eventPostFailed)

        let summary = accumulator.summary(sink: .live, sessionID: "session-1")
        XCTAssertEqual(summary.livePasteFailed, 1)
        XCTAssertEqual(accumulator.lastFailureReason, .eventPostFailed)
    }

    func testRecordingFinalAttemptedAndSucceededReflectsInSummary() {
        var accumulator = PasteSessionAccumulator()

        accumulator.recordFinalAttempted(chars: 12)
        accumulator.recordFinalSucceeded(chars: 12)

        let summary = accumulator.summary(sink: .batch, sessionID: "session-1")
        XCTAssertTrue(summary.finalPasteAttempted)
        XCTAssertTrue(summary.finalPasteSucceeded)
        XCTAssertEqual(summary.finalPasteCharsWritten, 12)
        XCTAssertNil(summary.finalPasteFailureReason)
    }

    func testFormatLogLineProducesLockedShape() {
        let nowBox = MutableNowBox(Date(timeIntervalSince1970: 10))
        var accumulator = PasteSessionAccumulator(now: { nowBox.value })
        accumulator.startedSession()
        accumulator.recordLiveAttempt(chars: 5)
        accumulator.recordLiveSucceeded(chars: 5)
        accumulator.recordLiveAttempt(chars: 4)
        accumulator.recordLiveClipboardWrite(chars: 4)
        accumulator.recordLiveSkipped()
        accumulator.recordFinalAttempted(chars: 12)
        accumulator.recordFinalClipboardWrite(chars: 12)
        accumulator.recordFinalFailed(reason: .eventPostFailed)
        accumulator.recordTarget(pid: 4321, bundleID: "com.apple.TextEdit")
        nowBox.value = Date(timeIntervalSince1970: 10.321)

        let summary = accumulator.summary(sink: .batch, sessionID: "session-123")

        XCTAssertEqual(
            summary.formatLogLine(),
            "paste_session_summary — sink=batch sessionID=session-123 livePasteAttempts=2 livePasteSucceeded=1 livePasteFailed=0 livePasteSkipped=1 livePasteCumulativeCharsWritten=9 finalPasteAttempted=true finalPasteSucceeded=false finalPasteCharsWritten=12 finalPasteFailureReason=eventPostFailed finalPasteSkipped=false targetAppPID=4321 targetAppBundleID=com.apple.TextEdit totalDurationMs=321"
        )
    }

    func testTotalDurationMsComputedFromStartedAtAndNow() {
        let nowBox = MutableNowBox(Date(timeIntervalSince1970: 100))
        var accumulator = PasteSessionAccumulator(now: { nowBox.value })

        accumulator.startedSession()
        nowBox.value = Date(timeIntervalSince1970: 101.75)

        let summary = accumulator.summary(sink: .live, sessionID: "session-1")
        XCTAssertEqual(summary.totalDurationMs, 1750)
    }
}
