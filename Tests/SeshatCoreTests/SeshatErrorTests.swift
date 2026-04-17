import XCTest
@testable import SeshatCore

final class SeshatErrorTests: XCTestCase {
    func testLocalizedDescriptions() {
        XCTAssertEqual(
            SeshatError.micPermissionDenied.errorDescription,
            "Microphone permission was denied."
        )
        XCTAssertEqual(
            SeshatError.transcriptionFailure.errorDescription,
            "Transcription failed."
        )
        XCTAssertEqual(
            SeshatError.invalidState.errorDescription,
            "The session entered an invalid state."
        )
    }
}
