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

    func testEffectiveDeviceIsSelectionWhileConnected() {
        let provider = StubInputDeviceProvider(available: ["usb", "built-in"], selected: "usb", systemDefault: "built-in")
        XCTAssertEqual(provider.effectiveDeviceID, "usb")
    }

    func testEffectiveDeviceFallsBackToDefaultWhileSelectionIsDisconnected() {
        let provider = StubInputDeviceProvider(available: ["built-in"], selected: "usb", systemDefault: "built-in")
        XCTAssertEqual(provider.effectiveDeviceID, "built-in")
        XCTAssertEqual(provider.selectedDeviceID, "usb", "choice is kept for when it reconnects")
    }
}

private final class StubInputDeviceProvider: AudioInputDeviceProviding, @unchecked Sendable {
    private let available: [String]
    let selectedDeviceID: String?
    let systemDefaultDeviceID: String?

    init(available: [String], selected: String?, systemDefault: String?) {
        self.available = available
        self.selectedDeviceID = selected
        self.systemDefaultDeviceID = systemDefault
    }

    func availableDevices() -> [AudioInputDevice] {
        available.map { AudioInputDevice(id: $0, name: $0) }
    }

    func selectDevice(id: String?) {}
}
