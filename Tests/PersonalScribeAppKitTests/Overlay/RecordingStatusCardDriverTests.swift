import XCTest
import PersonalScribeCore
@testable import PersonalScribeAppKit

final class RecordingStatusCardDriverTests: XCTestCase {
    func testRecordingWhileDownloadingShowsPercentText() {
        let text = RecordingStatusCardDriver.statusText(
            sessionState: .capturing,
            progress: .init(
                phase: .downloading,
                fractionCompleted: 0.25,
                receivedBytes: 25,
                expectedBytes: 100
            )
        )
        XCTAssertEqual(text, "Recording — transcribing when model is ready (25%)")
    }

    func testRecordingAtHundredPercentDownloadRoundsCleanly() {
        let text = RecordingStatusCardDriver.statusText(
            sessionState: .capturing,
            progress: .init(
                phase: .downloading,
                fractionCompleted: 0.997,
                receivedBytes: 997,
                expectedBytes: 1_000
            )
        )
        XCTAssertEqual(text, "Recording — transcribing when model is ready (100%)")
    }

    func testRecordingWhileLoadingShowsLoadingText() {
        let text = RecordingStatusCardDriver.statusText(
            sessionState: .capturing,
            progress: .init(
                phase: .loading,
                fractionCompleted: 1.0,
                receivedBytes: 100,
                expectedBytes: 100
            )
        )
        XCTAssertEqual(text, "Recording — model loading, transcription starts shortly")
    }

    func testTranscribingWhileDownloadingShowsWaitingText() {
        let text = RecordingStatusCardDriver.statusText(
            sessionState: .transcribing,
            progress: .init(
                phase: .downloading,
                fractionCompleted: 0.75,
                receivedBytes: 75,
                expectedBytes: 100
            )
        )
        XCTAssertEqual(text, "Waiting — finishing model download (75%)")
    }

    func testTranscribingWhileLoadingShowsWaitingText() {
        let text = RecordingStatusCardDriver.statusText(
            sessionState: .transcribing,
            progress: .init(
                phase: .loading,
                fractionCompleted: 1.0,
                receivedBytes: 0,
                expectedBytes: nil
            )
        )
        XCTAssertEqual(text, "Waiting — model loading")
    }

    func testIdleSessionReturnsNilEvenWithActiveProgress() {
        let text = RecordingStatusCardDriver.statusText(
            sessionState: .idle,
            progress: .init(
                phase: .downloading,
                fractionCompleted: 0.5,
                receivedBytes: 50,
                expectedBytes: 100
            )
        )
        XCTAssertNil(text)
    }

    func testFinishedPhaseReturnsNil() {
        let text = RecordingStatusCardDriver.statusText(
            sessionState: .capturing,
            progress: .init(
                phase: .finished,
                fractionCompleted: 1,
                receivedBytes: 100,
                expectedBytes: 100
            )
        )
        XCTAssertNil(text)
    }

    func testIdlePhaseReturnsNil() {
        let text = RecordingStatusCardDriver.statusText(
            sessionState: .capturing,
            progress: .init(
                phase: .idle,
                fractionCompleted: 0,
                receivedBytes: 0,
                expectedBytes: nil
            )
        )
        XCTAssertNil(text)
    }

    func testNilProgressReturnsNil() {
        let text = RecordingStatusCardDriver.statusText(
            sessionState: .capturing,
            progress: nil
        )
        XCTAssertNil(text)
    }

    func testErrorSessionReturnsNil() {
        let text = RecordingStatusCardDriver.statusText(
            sessionState: .error(.transcriptionFailure),
            progress: .init(
                phase: .downloading,
                fractionCompleted: 0.5,
                receivedBytes: 50,
                expectedBytes: 100
            )
        )
        XCTAssertNil(text)
    }

    // MARK: - Stage B (#046) — statusContent() driver

    /// Warning card must only appear when `showStoppingWarning` is on.
    /// Same inputs otherwise.
    func testDriverEmitsWarningOnlyWhenPrefOn() {
        let onContent = RecordingStatusCardDriver.statusContent(
            sessionState: .capturing,
            progress: nil,
            vadGracePending: true,
            vadFireToken: nil,
            vadLastSeenFireToken: nil,
            showStoppingWarning: true,
            showAutoStoppedNotification: false
        )
        XCTAssertEqual(onContent?.text, "…stopping, speak to continue")
        XCTAssertNil(onContent?.link)

        let offContent = RecordingStatusCardDriver.statusContent(
            sessionState: .capturing,
            progress: nil,
            vadGracePending: true,
            vadFireToken: nil,
            vadLastSeenFireToken: nil,
            showStoppingWarning: false,
            showAutoStoppedNotification: false
        )
        XCTAssertNil(offContent)
    }

    /// Notification must fire on every new token, then go quiet once
    /// the consumer advances its `lastSeenFireToken`. Re-firing is the
    /// job of the producer emitting a fresh token.
    func testDriverNotificationFiresOnceForEachToken() {
        let firstToken = UUID()
        let secondToken = UUID()

        let firstContent = RecordingStatusCardDriver.statusContent(
            sessionState: .transcribing,
            progress: nil,
            vadGracePending: false,
            vadFireToken: firstToken,
            vadLastSeenFireToken: nil,
            showStoppingWarning: false,
            showAutoStoppedNotification: true
        )
        XCTAssertEqual(firstContent?.text, "Auto stopped. Update settings to change.")
        XCTAssertNotNil(firstContent?.link)
        XCTAssertEqual(firstContent?.link?.action, .openVadSettings)
        if let text = firstContent?.text, let range = firstContent?.link?.range {
            XCTAssertEqual(String(text[range]), "Update settings to change")
        } else {
            XCTFail("expected link range inside notification content")
        }

        // Consumer has seen the token — same token must go quiet.
        let secondContent = RecordingStatusCardDriver.statusContent(
            sessionState: .transcribing,
            progress: nil,
            vadGracePending: false,
            vadFireToken: firstToken,
            vadLastSeenFireToken: firstToken,
            showStoppingWarning: false,
            showAutoStoppedNotification: true
        )
        XCTAssertNil(secondContent)

        // A fresh token reopens the notification.
        let thirdContent = RecordingStatusCardDriver.statusContent(
            sessionState: .transcribing,
            progress: nil,
            vadGracePending: false,
            vadFireToken: secondToken,
            vadLastSeenFireToken: firstToken,
            showStoppingWarning: false,
            showAutoStoppedNotification: true
        )
        XCTAssertEqual(thirdContent?.text, "Auto stopped. Update settings to change.")
        XCTAssertNotNil(thirdContent?.link)
    }

    /// `#075`: `.shortExit` is a non-error terminal. The pill is the
    /// sole surface for the "too short" chip; the card must render
    /// nothing for this state. Distinct from real errors, which still
    /// render on the card (see `testDriverErrorOverridesVadStates`).
    func testDriverEmitsNothingForShortExit() {
        let content = RecordingStatusCardDriver.statusContent(
            sessionState: .shortExit,
            progress: nil,
            vadGracePending: false,
            vadFireToken: nil,
            vadLastSeenFireToken: nil,
            showStoppingWarning: false,
            showAutoStoppedNotification: false
        )
        XCTAssertNil(content)
    }

    /// Error state must short-circuit before any VAD state is
    /// considered, even when grace + fire-token + both prefs are all
    /// active. Error > warning > notification.
    func testDriverErrorOverridesVadStates() {
        let token = UUID()
        let content = RecordingStatusCardDriver.statusContent(
            sessionState: .error(.resampleFailure),
            progress: nil,
            vadGracePending: true,
            vadFireToken: token,
            vadLastSeenFireToken: nil,
            showStoppingWarning: true,
            showAutoStoppedNotification: true
        )
        XCTAssertNotNil(content)
        XCTAssertNil(content?.link, "error branch must never carry a VAD settings link")
        XCTAssertNotEqual(
            content?.text,
            "…stopping, speak to continue",
            "grace warning must not fire when the session is in error"
        )
        XCTAssertNotEqual(
            content?.text,
            "Auto stopped. Update settings to change.",
            "auto-stopped notification must not fire when the session is in error"
        )
        XCTAssertEqual(
            content?.text,
            PersonalScribeError.resampleFailure.errorDescription
        )
    }
}
