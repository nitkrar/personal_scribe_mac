import XCTest
@testable import PersonalScribeCore

/// Minimal contract tests for `AudioInputDevice` — the value type
/// surfaced from `AudioInputDeviceProviding` to the menu-bar UI.
///
/// Reference: `plans/App UI design/Manus_Final_Bundle_Prompt.md` §2
/// (Microphone submenu, M5.3).
final class AudioInputDeviceTests: XCTestCase {
    func testIdentifiableConformanceExposesID() {
        // `Identifiable.id` must surface exactly the opaque device id
        // the provider gave us — renaming it, hashing it, or wrapping
        // it in the type would break the dispatch path where the
        // status-item controller hands this id to
        // `AudioInputDeviceProviding.selectDevice(id:)`.
        let device: any Identifiable = AudioInputDevice(id: "uid-42", name: "Audio")
        XCTAssertEqual(device.id as? String, "uid-42")
    }
}
