import AVFoundation
import Foundation
import XCTest
@testable import PersonalScribeAudio

/// Unit tests for the closure-forwarding surface of
/// `AudioEngineDriver.applyInputDevice(uid:)`. The real CoreAudio
/// enumeration path in `.live()` requires hardware fixtures (a second
/// input device, mounted CoreAudio HAL) and is covered by the manual-
/// verification runbook entry "M5.3 followup — microphone selection
/// takes effect" in `Tests/PersonalScribeAppKitTests/ManualVisualVerification.md`.
final class AudioEngineDriverApplyDeviceTests: XCTestCase {
    func testApplyInputDevicePropagatesClosureFailure() {
        struct BoomError: Error, Equatable {}
        let driver = makeDriver(
            applyInputDevice: { _ in throw BoomError() }
        )

        XCTAssertThrowsError(try driver.applyInputDevice(uid: "any")) { error in
            XCTAssertTrue(error is BoomError)
        }
    }

    // MARK: - Helpers

    private func makeDriver(
        applyInputDevice: @escaping (String?) throws -> Void
    ) -> AudioEngineDriver {
        guard
            let format = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: 44_100,
                channels: 1,
                interleaved: false
            )
        else {
            fatalError("AudioEngineDriverApplyDeviceTests: failed to create AVAudioFormat")
        }
        return AudioEngineDriver(
            inputFormatProvider: { format },
            installTap: { _ in },
            removeTap: {},
            prepare: {},
            start: {},
            stop: {},
            reset: {},
            applyInputDevice: applyInputDevice
        )
    }
}
