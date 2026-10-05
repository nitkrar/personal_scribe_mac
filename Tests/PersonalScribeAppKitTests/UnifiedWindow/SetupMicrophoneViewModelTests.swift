import Foundation
import XCTest
import PersonalScribeAudio
import PersonalScribeCore
@testable import PersonalScribeAppKit

@MainActor
final class SetupMicrophoneViewModelTests: XCTestCase {
    func testAppearLoadsDevicesAndStartsStandaloneMonitor() async {
        let provider = StubSetupInputDeviceProvider()
        let monitor = StubAudioLevelMonitor()
        let viewModel = SetupMicrophoneViewModel(
            inputDeviceProvider: provider,
            levelMonitor: monitor
        )

        await viewModel.appear()

        XCTAssertEqual(viewModel.devices, provider.devices)
        XCTAssertEqual(viewModel.selectedDeviceID, "built-in")
        XCTAssertTrue(viewModel.isMonitoring)
        let counts = await monitor.counts()
        XCTAssertEqual(counts.start, 1)
    }

    func testDisappearStopsStandaloneMonitor() async {
        let monitor = StubAudioLevelMonitor()
        let viewModel = SetupMicrophoneViewModel(
            inputDeviceProvider: StubSetupInputDeviceProvider(),
            levelMonitor: monitor
        )
        await viewModel.appear()

        await viewModel.disappear()

        XCTAssertFalse(viewModel.isMonitoring)
        let counts = await monitor.counts()
        XCTAssertEqual(counts.stop, 1)
    }

    func testRecordingActivityStopsMonitorBeforeItCanKeepTestingMic() async {
        let monitor = StubAudioLevelMonitor()
        let viewModel = SetupMicrophoneViewModel(
            inputDeviceProvider: StubSetupInputDeviceProvider(),
            levelMonitor: monitor
        )
        await viewModel.appear()

        await viewModel.recordingDidStart()

        XCTAssertFalse(viewModel.isMonitoring)
        let counts = await monitor.counts()
        XCTAssertEqual(counts.stop, 1)
    }

    func testSelectingDevicePersistsAndRestartsMonitor() async {
        let provider = StubSetupInputDeviceProvider()
        let monitor = StubAudioLevelMonitor()
        let viewModel = SetupMicrophoneViewModel(
            inputDeviceProvider: provider,
            levelMonitor: monitor
        )
        await viewModel.appear()

        await viewModel.selectDevice(id: "usb")

        XCTAssertEqual(provider.selectedDeviceID, "usb")
        XCTAssertEqual(viewModel.selectedDeviceID, "usb")
        let counts = await monitor.counts()
        XCTAssertEqual(counts.stop, 1)
        XCTAssertEqual(counts.start, 2)
    }
}

private final class StubSetupInputDeviceProvider: AudioInputDeviceProviding, @unchecked Sendable {
    let devices = [
        AudioInputDevice(id: "built-in", name: "MacBook Pro Microphone"),
        AudioInputDevice(id: "usb", name: "USB Microphone"),
    ]
    var selectedDeviceID: String? = "built-in"
    var systemDefaultDeviceID: String? = "built-in"

    func availableDevices() -> [AudioInputDevice] { devices }
    func selectDevice(id: String?) { selectedDeviceID = id }
}

private actor StubAudioLevelMonitor: AudioLevelMonitoring {
    private(set) var startCount = 0
    private(set) var stopCount = 0

    func start() async throws -> AsyncStream<Float> {
        startCount += 1
        return AsyncStream { continuation in
            continuation.yield(0.6)
        }
    }

    func stop() async {
        stopCount += 1
    }

    func counts() -> (start: Int, stop: Int) {
        (startCount, stopCount)
    }
}
