import XCTest
@testable import PersonalScribeCore

final class PersonalScribeErrorTests: XCTestCase {
    func testLocalizedErrorAccessorsCoverAllCases() {
        let expectations: [(error: PersonalScribeError, description: String, reason: String, suggestion: String)] = [
            (
                .micPermissionDenied,
                "Microphone permission was denied.",
                "The app does not have access to the microphone.",
                "Allow microphone access in System Settings and try again."
            ),
            (
                .audioEngineFailure,
                "Audio capture failed.",
                "The capture pipeline could not start or remain active.",
                "Try recording again."
            ),
            (
                .resampleFailure,
                "Audio resampling failed.",
                "The PCM buffer metadata was invalid or conversion failed.",
                "Try recording again."
            ),
            (
                .modelLoadFailure,
                "The transcription model could not be loaded.",
                "The speech model was unavailable or unreadable.",
                "Check model availability and try again."
            ),
            (
                .transcriptionFailure,
                "Transcription failed.",
                "The transcriber could not produce a result.",
                "Try transcribing the recording again."
            ),
            (
                .cancelled,
                "The operation was cancelled.",
                "The operation was stopped before it finished.",
                "Retry the operation if you still need it."
            ),
            (
                .invalidState,
                "The session entered an invalid state.",
                "A shared component detected an impossible transition or misuse.",
                "Reset the session and try again."
            )
        ]

        for expectation in expectations {
            XCTAssertEqual(expectation.error.errorDescription, expectation.description)
            XCTAssertEqual(expectation.error.failureReason, expectation.reason)
            XCTAssertEqual(expectation.error.recoverySuggestion, expectation.suggestion)
        }
    }
}
