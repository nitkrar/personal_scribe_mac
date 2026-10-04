import AVFoundation
import CoreAudio
import XCTest
import PersonalScribeCore
@testable import PersonalScribeAudio

/// Opt-in, real hardware: records from the default input and changes its
/// sample rate mid-recording, which posts the same configuration change a
/// Bluetooth headset's profile switch does (#110). Set
/// `NINIMMA_LIVE_DEVICE_TEST=1`; needs microphone permission.
final class LiveDeviceChangeTests: XCTestCase {
    func testRecordingSurvivesAnInputFormatChangeAndTheNextRecordingStarts() async throws {
        guard ProcessInfo.processInfo.environment["NINIMMA_LIVE_DEVICE_TEST"] == "1" else {
            throw XCTSkip("Set NINIMMA_LIVE_DEVICE_TEST=1 to run against the real default input")
        }
        guard await AVCaptureDevice.requestAccess(for: .audio) else {
            throw XCTSkip("Microphone permission denied for the test runner")
        }
        let device = try XCTUnwrap(Self.defaultInputDevice())
        let originalRate = try XCTUnwrap(Self.nominalRate(of: device))
        defer { Self.setNominalRate(originalRate, of: device) }
        Self.setNominalRate(48_000, of: device)
        try await Task.sleep(for: .milliseconds(500))

        let logger = PersonalScribeLogger(
            category: PersonalScribeLogCategory.audio,
            reporter: DiagnosticsReporter(sinks: [StderrSink()])
        )
        let service = AVAudioCaptureService(logger: logger)
        let counter = BufferCounter()

        let first = try await service.start()
        let firstConsumer = Task { for try await _ in first { counter.increment() } }
        try await Task.sleep(for: .seconds(1))
        let beforeChange = counter.value
        XCTAssertGreaterThan(beforeChange, 0, "audio flows at 48 kHz")

        Self.setNominalRate(44_100, of: device)
        try await Task.sleep(for: .seconds(2))
        XCTAssertEqual(Self.nominalRate(of: device), 44_100, "the hardware rate actually changed")
        let afterChange = counter.value
        XCTAssertGreaterThan(afterChange, beforeChange + 5, "audio keeps flowing after the format change")

        await service.stop()
        _ = try? await firstConsumer.value

        let second = try await service.start()
        let secondConsumer = Task { for try await _ in second { counter.increment() } }
        try await Task.sleep(for: .seconds(1))
        XCTAssertGreaterThan(counter.value, afterChange + 5, "the next recording starts at the new rate")
        await service.stop()
        _ = try? await secondConsumer.value
    }

    /// The AirPods case: the input in use disappears mid-recording and
    /// macOS falls back to another device. A temporary aggregate device
    /// wrapping the built-in mic stands in for the headset.
    func testRecordingSurvivesTheInputDeviceDisappearing() async throws {
        guard ProcessInfo.processInfo.environment["NINIMMA_LIVE_DEVICE_TEST"] == "1" else {
            throw XCTSkip("Set NINIMMA_LIVE_DEVICE_TEST=1 to run against the real default input")
        }
        guard await AVCaptureDevice.requestAccess(for: .audio) else {
            throw XCTSkip("Microphone permission denied for the test runner")
        }
        let original = try XCTUnwrap(Self.defaultInputDevice())
        var aggregate = try XCTUnwrap(Self.createAggregate(wrapping: "BuiltInMicrophoneDevice"))
        defer {
            Self.setDefaultInput(original)
            if aggregate != 0 { AudioHardwareDestroyAggregateDevice(aggregate) }
        }
        Self.setDefaultInput(aggregate)
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertEqual(Self.defaultInputDevice(), aggregate, "the stand-in headset is the default input")

        let logger = PersonalScribeLogger(
            category: PersonalScribeLogCategory.audio,
            reporter: DiagnosticsReporter(sinks: [StderrSink()])
        )
        let service = AVAudioCaptureService(logger: logger)
        let counter = BufferCounter()

        let stream = try await service.start()
        let consumer = Task { for try await _ in stream { counter.increment() } }
        try await Task.sleep(for: .seconds(1))
        let before = counter.value
        XCTAssertGreaterThan(before, 0)

        AudioHardwareDestroyAggregateDevice(aggregate)
        aggregate = 0
        try await Task.sleep(for: .seconds(2))
        XCTAssertNotEqual(Self.defaultInputDevice(), nil)
        XCTAssertGreaterThan(counter.value, before + 5, "audio keeps flowing from the fallback device")

        await service.stop()
        _ = try? await consumer.value

        let next = try await service.start()
        let nextConsumer = Task { for try await _ in next { counter.increment() } }
        let afterDisappear = counter.value
        try await Task.sleep(for: .seconds(1))
        XCTAssertGreaterThan(counter.value, afterDisappear + 5, "the next recording starts")
        await service.stop()
        _ = try? await nextConsumer.value
    }

    /// Both directions in one recording: a headset connects, then leaves.
    func testRecordingFollowsAnInputThatAppearsThenDisappears() async throws {
        guard ProcessInfo.processInfo.environment["NINIMMA_LIVE_DEVICE_TEST"] == "1" else {
            throw XCTSkip("Set NINIMMA_LIVE_DEVICE_TEST=1 to run against the real default input")
        }
        guard await AVCaptureDevice.requestAccess(for: .audio) else {
            throw XCTSkip("Microphone permission denied for the test runner")
        }
        let original = try XCTUnwrap(Self.defaultInputDevice())
        var aggregate = AudioDeviceID(0)
        defer {
            Self.setDefaultInput(original)
            if aggregate != 0 { AudioHardwareDestroyAggregateDevice(aggregate) }
        }

        let logger = PersonalScribeLogger(
            category: PersonalScribeLogCategory.audio,
            reporter: DiagnosticsReporter(sinks: [StderrSink()])
        )
        let service = AVAudioCaptureService(logger: logger)
        let counter = BufferCounter()
        let stream = try await service.start()
        let consumer = Task { for try await _ in stream { counter.increment() } }
        try await Task.sleep(for: .seconds(1))
        let onOriginal = counter.value
        XCTAssertGreaterThan(onOriginal, 0)

        aggregate = try XCTUnwrap(Self.createAggregate(wrapping: "BuiltInMicrophoneDevice"))
        Self.setDefaultInput(aggregate)
        try await Task.sleep(for: .seconds(2))
        XCTAssertEqual(Self.defaultInputDevice(), aggregate)
        let onHeadset = counter.value
        XCTAssertGreaterThan(onHeadset, onOriginal + 5, "audio flows after the headset connects")

        AudioHardwareDestroyAggregateDevice(aggregate)
        aggregate = 0
        try await Task.sleep(for: .seconds(2))
        XCTAssertGreaterThan(counter.value, onHeadset + 5, "audio flows after the headset leaves")

        await service.stop()
        _ = try? await consumer.value
    }

    private static func createAggregate(wrapping subDeviceUID: String) -> AudioDeviceID? {
        let description: [String: Any] = [
            kAudioAggregateDeviceUIDKey: "ninimma.test.aggregate.\(UUID().uuidString)",
            kAudioAggregateDeviceNameKey: "Ninimma Test Headset",
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: subDeviceUID]],
            kAudioAggregateDeviceMainSubDeviceKey: subDeviceUID,
        ]
        var id = AudioDeviceID(0)
        let status = AudioHardwareCreateAggregateDevice(description as CFDictionary, &id)
        return status == noErr ? id : nil
    }

    private static func inputDevice(named name: String) -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size = UInt32(0)
        AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size)
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids)
        return ids.first { id in
            var nameAddress = AudioObjectPropertyAddress(
                mSelector: kAudioObjectPropertyName,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var cfName: CFString = "" as CFString
            var nameSize = UInt32(MemoryLayout<CFString>.size)
            AudioObjectGetPropertyData(id, &nameAddress, 0, nil, &nameSize, &cfName)
            return (cfName as String).contains(name)
        }
    }

    private static func setDefaultInput(_ device: AudioDeviceID) {
        var value = device
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, UInt32(MemoryLayout<AudioDeviceID>.size), &value)
    }

    private static func defaultInputDevice() -> AudioDeviceID? {
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &id)
        return status == noErr ? id : nil
    }

    private static func nominalRate(of device: AudioDeviceID) -> Float64? {
        var rate = Float64(0)
        var size = UInt32(MemoryLayout<Float64>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        return AudioObjectGetPropertyData(device, &address, 0, nil, &size, &rate) == noErr ? rate : nil
    }

    private static func setNominalRate(_ rate: Float64, of device: AudioDeviceID) {
        var value = rate
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<Float64>.size), &value)
    }
}

private final class BufferCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var value: Int { lock.withLock { count } }
    func increment() { lock.withLock { count += 1 } }
}

private struct StderrSink: DiagnosticsSink {
    func record(_ event: RedactedDiagnosticsEvent) async {
        FileHandle.standardError.write(Data("[capture] \(event.message) \(event.underlyingError ?? "")\n".utf8))
    }
}
