import XCTest
@testable import PersonalScribeAudio
import PersonalScribeCore

/// UserDefaults round-trip tests for `AVFoundationInputDeviceProvider`.
///
/// We do NOT exercise `availableDevices()` here — that would require
/// hardware fixtures and would cover AVFoundation behavior rather than
/// our own logic. Hardware enumeration is covered by
/// `Tests/PersonalScribeAudioTests/ManualAudioCaptureVerification.md`.
///
/// Reference: `plans/App UI design/Manus_Final_Bundle_Prompt.md` §2.
final class AVFoundationInputDeviceProviderTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        // Unique per-test UserDefaults suite so runs are isolated and
        // so we never touch `.standard`.
        suiteName = "AVFoundationInputDeviceProviderTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testSelectedDeviceIDIsNilOnEmptyDefaults() {
        let provider = AVFoundationInputDeviceProvider(defaults: defaults)
        XCTAssertNil(provider.selectedDeviceID)
    }

    func testSelectDevicePersistsID() {
        let provider = AVFoundationInputDeviceProvider(defaults: defaults)
        provider.selectDevice(id: "uid-builtin")

        XCTAssertEqual(provider.selectedDeviceID, "uid-builtin")
        // Independent probe to confirm the write hit the UserDefaults
        // key the rest of the app (and any external tooling) expects.
        XCTAssertEqual(
            defaults.string(forKey: AVFoundationInputDeviceProvider.userDefaultsKey),
            "uid-builtin"
        )
    }

    func testSelectDeviceWithNilClearsPreviousSelection() {
        let provider = AVFoundationInputDeviceProvider(defaults: defaults)
        provider.selectDevice(id: "uid-builtin")
        XCTAssertEqual(provider.selectedDeviceID, "uid-builtin")

        provider.selectDevice(id: nil)
        XCTAssertNil(provider.selectedDeviceID)
        XCTAssertNil(defaults.string(forKey: AVFoundationInputDeviceProvider.userDefaultsKey))
    }

    func testEmptyStringSelectionClearsPreviousSelection() {
        // An empty string is meaningless as a device identifier and
        // would otherwise round-trip as a real selection — which
        // would confuse the menu model's "match selection to current
        // device" lookup. Treat it the same as `nil`.
        let provider = AVFoundationInputDeviceProvider(defaults: defaults)
        provider.selectDevice(id: "uid-builtin")
        provider.selectDevice(id: "")

        XCTAssertNil(provider.selectedDeviceID)
    }

    func testSelectDeviceOverwritesExistingSelection() {
        let provider = AVFoundationInputDeviceProvider(defaults: defaults)
        provider.selectDevice(id: "uid-a")
        provider.selectDevice(id: "uid-b")

        XCTAssertEqual(provider.selectedDeviceID, "uid-b")
    }

    func testSecondProviderInstanceSeesPersistedSelection() {
        // Simulates a relaunch: a fresh provider wrapping the same
        // UserDefaults suite must surface the previously-persisted id.
        let first = AVFoundationInputDeviceProvider(defaults: defaults)
        first.selectDevice(id: "uid-shared")

        let second = AVFoundationInputDeviceProvider(defaults: defaults)
        XCTAssertEqual(second.selectedDeviceID, "uid-shared")
    }
}
