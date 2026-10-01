import XCTest
@testable import PersonalScribeCore

final class NonSpeechMarkerFilterTests: XCTestCase {
    func testStripsWhisperBracketMarkers() {
        XCTAssertEqual(NonSpeechMarkerFilter.strip("[BLANK_AUDIO]"), "")
        XCTAssertEqual(NonSpeechMarkerFilter.strip("Send it today. [BLANK_AUDIO]"), "Send it today.")
        XCTAssertEqual(NonSpeechMarkerFilter.strip("Okay [ Silence ] then"), "Okay then")
        XCTAssertEqual(NonSpeechMarkerFilter.strip("[MUSIC] Thanks"), "Thanks")
    }

    func testStripsParenthesizedSoundDescriptionsButKeepsDictatedParentheses() {
        XCTAssertEqual(NonSpeechMarkerFilter.strip("(upbeat music) Thanks"), "Thanks")
        XCTAssertEqual(NonSpeechMarkerFilter.strip("Right. (coughs)"), "Right.")
        XCTAssertEqual(
            NonSpeechMarkerFilter.strip("Call me (maybe) later"),
            "Call me (maybe) later"
        )
    }

    func testResultFilteringDropsMarkerOnlySegments() {
        let result = TranscriptionResult(
            text: "Hello there. [BLANK_AUDIO]",
            segments: [
                .init(text: "Hello there.", start: .zero, end: .seconds(1)),
                .init(text: "[BLANK_AUDIO]", start: .seconds(1), end: .seconds(2)),
            ],
            audioDuration: .seconds(2),
            processingDuration: .milliseconds(100)
        )

        let filtered = result.removingNonSpeechMarkers()

        XCTAssertEqual(filtered.text, "Hello there.")
        XCTAssertEqual(filtered.segments.map(\.text), ["Hello there."])
        XCTAssertEqual(filtered.audioDuration, result.audioDuration)
    }
}
