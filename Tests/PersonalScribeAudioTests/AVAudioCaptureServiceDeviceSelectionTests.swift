import AVFoundation
import Foundation
import XCTest
import PersonalScribeCore
@testable import PersonalScribeAudio

/// Tests for the M5.3 followup wiring: the persisted
/// `SelectedAudioInputDeviceID` in `AudioInputDeviceProviding` must be
/// applied to the engine before recording begins, and a failure in that
/// device-apply step must not block the overall recording start.
final class AVAudioCaptureServiceDeviceSelectionTests: XCTestCase {
    func testStartAppliesProviderSelectedDeviceUIDBeforeDriverStart() async throws {
        let order = CallOrderTracker()
        let box = ThreadSafeEngineBox()
        let driver = AudioEngineDriver.testStubTrackingOrder(box: box, order: order)
        let provider = FakeInputDeviceProvider(selectedDeviceID: "test-device")

        let service = AVAudioCaptureService(
            logger: PersonalScribeLogger.testing(category: PersonalScribeLogCategory.audio),
            authorizationStatusProvider: { .authorized },
            engineDriver: driver,
            resamplerFactory: { rate, logger in
                try AudioResampler(inputSampleRate: rate, logger: logger)
            },
            inputDeviceProvider: provider
        )

        _ = try await service.start()

        let expectedUIDs: [String?] = ["test-device"]
        XCTAssertEqual(order.capturedUIDs, expectedUIDs)
        let events = order.events
        guard
            let applyIndex = events.firstIndex(of: "applyInputDevice"),
            let startIndex = events.firstIndex(of: "start")
        else {
            XCTFail("Expected both applyInputDevice and start events, got \(events)")
            return
        }
        XCTAssertLessThan(
            applyIndex,
            startIndex,
            "applyInputDevice must happen before driver.start() — saw events: \(events)"
        )

        await service.stop()
    }

    func testStartForwardsNilUIDWhenProviderHasNoSelection() async throws {
        let order = CallOrderTracker()
        let box = ThreadSafeEngineBox()
        let driver = AudioEngineDriver.testStubTrackingOrder(box: box, order: order)
        let provider = FakeInputDeviceProvider(selectedDeviceID: nil)

        let service = AVAudioCaptureService(
            logger: PersonalScribeLogger.testing(category: PersonalScribeLogCategory.audio),
            authorizationStatusProvider: { .authorized },
            engineDriver: driver,
            resamplerFactory: { rate, logger in
                try AudioResampler(inputSampleRate: rate, logger: logger)
            },
            inputDeviceProvider: provider
        )

        _ = try await service.start()

        XCTAssertEqual(order.capturedUIDs.count, 1)
        // `[String?].first` returns `String??`; flatten via `?? nil` to
        // `String?` so `XCTAssertNil` asserts the inner value is nil.
        let forwarded: String? = order.capturedUIDs.first ?? nil
        XCTAssertNil(forwarded)

        await service.stop()
    }

    func testStartSwallowsApplyInputDeviceFailureAndStillStartsEngine() async throws {
        struct BoomError: Error {}
        let order = CallOrderTracker()
        let box = ThreadSafeEngineBox()
        let driver = AudioEngineDriver.testStubTrackingOrder(
            box: box,
            order: order,
            applyInputDeviceError: BoomError()
        )
        let provider = FakeInputDeviceProvider(selectedDeviceID: "will-fail")

        let service = AVAudioCaptureService(
            logger: PersonalScribeLogger.testing(category: PersonalScribeLogCategory.audio),
            authorizationStatusProvider: { .authorized },
            engineDriver: driver,
            resamplerFactory: { rate, logger in
                try AudioResampler(inputSampleRate: rate, logger: logger)
            },
            inputDeviceProvider: provider
        )

        // Must NOT throw — apply failures are logged and swallowed.
        _ = try await service.start()

        XCTAssertEqual(box.startCount, 1, "driver.start() must still run after applyInputDevice failure")
        XCTAssertTrue(
            order.events.contains("start"),
            "driver.start() must still run after applyInputDevice failure"
        )

        await service.stop()
    }
}

// MARK: - Helpers

/// Minimal `AudioInputDeviceProviding` stub. Unit tests don't exercise
/// the `availableDevices` / `selectDevice` methods — only
/// `selectedDeviceID` is consumed by `AVAudioCaptureService.start()`.
private final class FakeInputDeviceProvider: AudioInputDeviceProviding, @unchecked Sendable {
    let selectedDeviceID: String?

    init(selectedDeviceID: String?) {
        self.selectedDeviceID = selectedDeviceID
    }

    func availableDevices() -> [AudioInputDevice] { [] }
    func selectDevice(id: String?) {}
}

/// Records the order of driver lifecycle calls so tests can assert
/// that `applyInputDevice` runs before `start` and capture the forwarded
/// UID argument.
final class CallOrderTracker: @unchecked Sendable {
    // Safe in tests: NSLock protects mutable event/uid lists.
    private let lock = NSLock()
    private var _events: [String] = []
    private var _capturedUIDs: [String?] = []

    func record(_ event: String) {
        lock.lock()
        defer { lock.unlock() }
        _events.append(event)
    }

    func recordApply(uid: String?) {
        lock.lock()
        defer { lock.unlock() }
        _events.append("applyInputDevice")
        _capturedUIDs.append(uid)
    }

    var events: [String] {
        lock.lock()
        defer { lock.unlock() }
        return _events
    }

    var capturedUIDs: [String?] {
        lock.lock()
        defer { lock.unlock() }
        return _capturedUIDs
    }
}

extension AudioEngineDriver {
    /// Test-only driver variant that records lifecycle call order into a
    /// shared `CallOrderTracker` in addition to the existing counters on
    /// `ThreadSafeEngineBox`. Used exclusively by
    /// `AVAudioCaptureServiceDeviceSelectionTests` to assert that
    /// `applyInputDevice` happens before `start`.
    static func testStubTrackingOrder(
        sampleRate: Double = 44_100,
        channels: Int = 1,
        box: ThreadSafeEngineBox,
        order: CallOrderTracker,
        applyInputDeviceError: Error? = nil
    ) -> AudioEngineDriver {
        guard
            let format = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: sampleRate,
                channels: AVAudioChannelCount(channels),
                interleaved: false
            )
        else {
            fatalError("testStubTrackingOrder: failed to create AVAudioFormat")
        }
        return AudioEngineDriver(
            inputFormatProvider: { format },
            installTap: { handler in
                order.record("installTap")
                box.setHandler(handler)
            },
            removeTap: {
                order.record("removeTap")
                box.clearHandler()
            },
            prepare: {
                order.record("prepare")
                box.recordPrepare()
            },
            start: {
                order.record("start")
                try box.recordStart()
            },
            stop: {
                order.record("stop")
                box.recordStop()
            },
            reset: {
                order.record("reset")
                box.recordReset()
            },
            applyInputDevice: { uid in
                order.recordApply(uid: uid)
                if let applyInputDeviceError {
                    throw applyInputDeviceError
                }
            }
        )
    }
}
