import XCTest
import Combine
import PersonalScribeCore
@testable import PersonalScribeAppKit

/// Tests for `MicrophoneFooterViewModel` — the sidebar footer readout
/// of the currently-configured input device (issue #008).
///
/// The view model is pure / protocol-injectable: a fake
/// `AudioInputDeviceProviding` drives the input, and a `UserDefaults`
/// instance backed by `volatileDomain` simulates the live-update path
/// exercised when the menu-bar Microphone submenu writes a new
/// selection under `SelectedAudioInputDeviceID`.
@MainActor
final class MicrophoneFooterViewModelTests: XCTestCase {
    // MARK: - Fakes

    /// Mutable `AudioInputDeviceProviding` double. Callers tweak
    /// `availableDevicesValue` / `selectedDeviceIDValue` between
    /// assertions to model hotplug + selection-change scenarios.
    final class FakeProvider: AudioInputDeviceProviding, @unchecked Sendable {
        var availableDevicesValue: [AudioInputDevice]
        var selectedDeviceIDValue: String?

        init(
            devices: [AudioInputDevice] = [],
            selectedID: String? = nil
        ) {
            self.availableDevicesValue = devices
            self.selectedDeviceIDValue = selectedID
        }

        func availableDevices() -> [AudioInputDevice] { availableDevicesValue }
        var selectedDeviceID: String? { selectedDeviceIDValue }
        func selectDevice(id: String?) { selectedDeviceIDValue = id }
    }

    // MARK: - Helpers

    private func makeDefaults(suiteName: String = UUID().uuidString) -> UserDefaults {
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    // MARK: - Initial state

    func testCurrentDeviceNameReflectsProviderSelectionOnInit() {
        let devices = [
            AudioInputDevice(id: "uid-built-in", name: "MacBook Pro Microphone"),
            AudioInputDevice(id: "uid-airpods", name: "AirPods Pro"),
        ]
        let provider = FakeProvider(devices: devices, selectedID: "uid-airpods")
        let model = MicrophoneFooterViewModel(
            provider: provider,
            defaults: makeDefaults()
        )

        XCTAssertEqual(model.currentDeviceName, "AirPods Pro")
    }

    func testCurrentDeviceNameIsNilWhenNoSelectionAndNoDevices() {
        let provider = FakeProvider(devices: [], selectedID: nil)
        let model = MicrophoneFooterViewModel(
            provider: provider,
            defaults: makeDefaults()
        )

        XCTAssertNil(model.currentDeviceName)
    }

    func testCurrentDeviceNameFallsBackToSystemDefaultLabelWhenSelectionMissingButDevicesPresent() {
        // No persisted selection — user is on macOS default input, which
        // the provider's `availableDevices()` surfaces as the first entry
        // returned by the AV discovery session. The view model cannot
        // distinguish "system default" from "first available" with the
        // pull-only protocol, so it reports nil and the view falls back
        // to a generic label.
        let devices = [
            AudioInputDevice(id: "uid-built-in", name: "MacBook Pro Microphone"),
        ]
        let provider = FakeProvider(devices: devices, selectedID: nil)
        let model = MicrophoneFooterViewModel(
            provider: provider,
            defaults: makeDefaults()
        )

        XCTAssertNil(model.currentDeviceName)
    }

    func testCurrentDeviceNameIsNilWhenSelectedDeviceDisappeared() {
        // User previously picked a USB mic; device has been unplugged.
        // availableDevices() no longer contains the persisted ID.
        let devices = [
            AudioInputDevice(id: "uid-built-in", name: "MacBook Pro Microphone"),
        ]
        let provider = FakeProvider(devices: devices, selectedID: "uid-airpods-gone")
        let model = MicrophoneFooterViewModel(
            provider: provider,
            defaults: makeDefaults()
        )

        XCTAssertNil(model.currentDeviceName)
    }

    // MARK: - Live updates via UserDefaults.didChangeNotification

    func testRefreshRepublishesWhenSelectionChanges() {
        let devices = [
            AudioInputDevice(id: "uid-built-in", name: "MacBook Pro Microphone"),
            AudioInputDevice(id: "uid-airpods", name: "AirPods Pro"),
        ]
        let provider = FakeProvider(devices: devices, selectedID: "uid-built-in")
        let model = MicrophoneFooterViewModel(
            provider: provider,
            defaults: makeDefaults()
        )

        XCTAssertEqual(model.currentDeviceName, "MacBook Pro Microphone")

        // Menu-bar submenu has just called selectDevice(id:) — the
        // provider now returns a different selection, and the view
        // model is asked to refresh (either by a UserDefaults
        // notification or an explicit call).
        provider.selectedDeviceIDValue = "uid-airpods"
        model.refresh()

        XCTAssertEqual(model.currentDeviceName, "AirPods Pro")
    }

    func testRefreshRepublishesWhenDeviceDisappears() {
        let devices = [
            AudioInputDevice(id: "uid-built-in", name: "MacBook Pro Microphone"),
            AudioInputDevice(id: "uid-airpods", name: "AirPods Pro"),
        ]
        let provider = FakeProvider(devices: devices, selectedID: "uid-airpods")
        let model = MicrophoneFooterViewModel(
            provider: provider,
            defaults: makeDefaults()
        )

        XCTAssertEqual(model.currentDeviceName, "AirPods Pro")

        // User unplugs AirPods mid-session. Selection persists but
        // the device is no longer enumerable.
        provider.availableDevicesValue = [
            AudioInputDevice(id: "uid-built-in", name: "MacBook Pro Microphone"),
        ]
        model.refresh()

        XCTAssertNil(model.currentDeviceName)
    }

    func testUserDefaultsSelectionChangePushesUpdateAutomatically() {
        let suite = "test.microphone-footer.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let devices = [
            AudioInputDevice(id: "uid-built-in", name: "MacBook Pro Microphone"),
            AudioInputDevice(id: "uid-airpods", name: "AirPods Pro"),
        ]
        let provider = FakeProvider(devices: devices, selectedID: "uid-built-in")
        let model = MicrophoneFooterViewModel(
            provider: provider,
            defaults: defaults
        )

        XCTAssertEqual(model.currentDeviceName, "MacBook Pro Microphone")

        // Simulate the menu-bar submenu persisting a new selection.
        provider.selectedDeviceIDValue = "uid-airpods"
        defaults.set("uid-airpods", forKey: "SelectedAudioInputDeviceID")

        // The didChangeNotification fires synchronously on `.set(_:forKey:)`
        // for the same process, so by the next main-thread turn the
        // view model should have refreshed. Pump the run loop briefly.
        let expectation = expectation(description: "published update propagates")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)

        XCTAssertEqual(model.currentDeviceName, "AirPods Pro")
    }

    // MARK: - Published hook

    func testPublishedChangeFiresWhenNameChanges() {
        let devices = [
            AudioInputDevice(id: "uid-built-in", name: "MacBook Pro Microphone"),
            AudioInputDevice(id: "uid-airpods", name: "AirPods Pro"),
        ]
        let provider = FakeProvider(devices: devices, selectedID: "uid-built-in")
        let model = MicrophoneFooterViewModel(
            provider: provider,
            defaults: makeDefaults()
        )

        var observedNames: [String?] = []
        let cancellable = model.$currentDeviceName.sink { name in
            observedNames.append(name)
        }
        defer { cancellable.cancel() }

        provider.selectedDeviceIDValue = "uid-airpods"
        model.refresh()

        // Initial emission (Combine's `sink` fires synchronously with
        // the current value) plus one more after the refresh.
        XCTAssertEqual(observedNames, ["MacBook Pro Microphone", "AirPods Pro"])
    }
}
