import XCTest
import PersonalScribeCore
@testable import PersonalScribeAppKit

final class RecordingStatusCardDriverTests: XCTestCase {
    func testRecordingWhileDownloadingShowsPercentText() {
        let text = RecordingStatusCardDriver.statusText(
            sessionState: .recording,
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
            sessionState: .recording,
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
            sessionState: .recording,
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
            sessionState: .recording,
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
            sessionState: .recording,
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
            sessionState: .recording,
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
}
