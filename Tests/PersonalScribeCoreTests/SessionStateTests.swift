import XCTest
@testable import PersonalScribeCore

final class SessionStateTests: XCTestCase {
    func testErrorEqualityUsesMappedPersonalScribeErrorOnly() {
        XCTAssertEqual(
            SessionState.error(.audioEngineFailure),
            SessionState.error(.audioEngineFailure)
        )
        XCTAssertNotEqual(
            SessionState.error(.audioEngineFailure),
            SessionState.error(.transcriptionFailure)
        )
    }

    /// #071 — Hold-to-record must be a first-class state distinct from
    /// `.recording` so the store can derive `.holdToRecord` without a
    /// side-channel push from the hotkey layer.
    func testHoldRecordingIsDistinctFromRecording() {
        XCTAssertNotEqual(SessionState.holdRecording, SessionState.recording)
        XCTAssertEqual(SessionState.holdRecording, SessionState.holdRecording)
        XCTAssertNotEqual(SessionState.holdRecording, SessionState.idle)
        XCTAssertNotEqual(SessionState.holdRecording, SessionState.transcribing)
    }
}
