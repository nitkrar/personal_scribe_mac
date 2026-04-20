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
    func testApplyInputDeviceWithNilUIDInvokesSystemDefaultPath() throws {
        let captured = CapturedUID()
        let driver = makeDriver(captured: captured)

        try driver.applyInputDevice(uid: nil)

        XCTAssertEqual(captured.callCount, 1)
        XCTAssertNil(captured.lastUID)
        XCTAssertTrue(captured.lastUIDWasNil)
    }

    func testApplyInputDeviceWithUIDForwardsToClosure() throws {
        let captured = CapturedUID()
        let driver = makeDriver(captured: captured)

        try driver.applyInputDevice(uid: "test-uid")

        XCTAssertEqual(captured.callCount, 1)
        XCTAssertEqual(captured.lastUID, "test-uid")
        XCTAssertFalse(captured.lastUIDWasNil)
    }

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
        captured: CapturedUID
    ) -> AudioEngineDriver {
        makeDriver(applyInputDevice: { uid in
            captured.record(uid: uid)
        })
    }

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

/// Records every invocation of the injected apply-device closure so tests
/// can assert forwarded arguments + call counts without relying on the
/// real CoreAudio HAL.
private final class CapturedUID: @unchecked Sendable {
    // Safe in tests: NSLock protects mutable state shared across the
    // potential test queue and assertions.
    private let lock = NSLock()
    private var _callCount = 0
    private var _lastUID: String?
    private var _lastUIDWasNil = false

    func record(uid: String?) {
        lock.lock()
        defer { lock.unlock() }
        _callCount += 1
        _lastUID = uid
        _lastUIDWasNil = uid == nil
    }

    var callCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return _callCount
    }

    var lastUID: String? {
        lock.lock()
        defer { lock.unlock() }
        return _lastUID
    }

    var lastUIDWasNil: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _lastUIDWasNil
    }
}
