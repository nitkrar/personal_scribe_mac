import XCTest
import SeshatCore
@testable import SeshatAppKit

@MainActor
final class MenuBarStatusIconTests: XCTestCase {
    func testGrantedIdleMapsToMic() {
        let icon = MenuBarStatusIcon.make(sessionState: .idle, permissionState: .granted)

        XCTAssertEqual(icon.systemImageName, "mic")
        XCTAssertEqual(icon.accessibilityLabel, "Idle")
        XCTAssertFalse(icon.showsActiveAccent)
    }

    func testGrantedRecordingMapsToFilledMicWithActiveAccent() {
        let icon = MenuBarStatusIcon.make(sessionState: .recording, permissionState: .granted)

        XCTAssertEqual(icon.systemImageName, "mic.fill")
        XCTAssertEqual(icon.accessibilityLabel, "Recording")
        XCTAssertTrue(icon.showsActiveAccent)
    }

    func testDeniedAlwaysMapsToMicSlash() {
        let icon = MenuBarStatusIcon.make(
            sessionState: .transcribing,
            permissionState: .denied
        )

        XCTAssertEqual(icon.systemImageName, "mic.slash")
        XCTAssertEqual(icon.accessibilityLabel, "Microphone permission denied")
        XCTAssertFalse(icon.showsActiveAccent)
    }
}
