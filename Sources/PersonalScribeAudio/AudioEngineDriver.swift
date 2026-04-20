import AVFoundation
import CoreAudio
import Foundation

/// Internal seam around `AVAudioEngine`'s input tap lifecycle. Production uses
/// `.live()`; tests inject their own closures.
///
/// Kept as a class (not an actor) because AVFoundation's tap callbacks fire on
/// real-time threads and cannot be actor-isolated. Instances are held behind
/// `AVAudioCaptureService`'s actor, which serializes the only public entry
/// points that mutate driver state.
internal final class AudioEngineDriver: @unchecked Sendable {
    // Safe: lifecycle mutations are serialized by the owning AVAudioCaptureService
    // actor; the tap callback is the only concurrent caller and only reads the
    // installed handler (no mutation).

    internal init(
        inputFormatProvider: @escaping () -> AVAudioFormat,
        installTap: @escaping (
            @escaping @Sendable (AVAudioPCMBuffer, AVAudioTime) -> Void
        ) throws -> Void,
        removeTap: @escaping () -> Void,
        prepare: @escaping () -> Void,
        start: @escaping () throws -> Void,
        stop: @escaping () -> Void,
        reset: @escaping () -> Void,
        applyInputDevice: @escaping (String?) throws -> Void = { _ in }
    ) {
        self.inputFormatProvider = inputFormatProvider
        self.installTapImpl = installTap
        self.removeTapImpl = removeTap
        self.prepareImpl = prepare
        self.startImpl = start
        self.stopImpl = stop
        self.resetImpl = reset
        self.applyInputDeviceImpl = applyInputDevice
    }

    internal static func live() -> AudioEngineDriver {
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode

        return AudioEngineDriver(
            inputFormatProvider: { inputNode.outputFormat(forBus: 0) },
            installTap: { handler in
                inputNode.installTap(
                    onBus: 0,
                    bufferSize: 4_096,
                    format: inputNode.outputFormat(forBus: 0)
                ) { buffer, when in
                    handler(buffer, when)
                }
            },
            removeTap: {
                inputNode.removeTap(onBus: 0)
            },
            prepare: {
                engine.prepare()
            },
            start: {
                try engine.start()
            },
            stop: {
                engine.stop()
            },
            reset: {
                engine.reset()
            },
            applyInputDevice: { uid in
                try AudioEngineDriver.applyInputDeviceLive(uid: uid, inputNode: inputNode)
            }
        )
    }

    internal func inputFormat() -> AVAudioFormat { inputFormatProvider() }
    internal func installTap(_ handler: @escaping @Sendable (AVAudioPCMBuffer, AVAudioTime) -> Void) throws {
        try installTapImpl(handler)
    }
    internal func removeTap() { removeTapImpl() }
    internal func prepare() { prepareImpl() }
    internal func start() throws { try startImpl() }
    internal func stop() { stopImpl() }
    internal func reset() { resetImpl() }

    /// Apply the user-selected CoreAudio input device (matched by
    /// `AVCaptureDevice.uniqueID`, which maps 1:1 to
    /// `kAudioDevicePropertyDeviceUID` on macOS) to the underlying
    /// `AVAudioEngine.inputNode`. Passing `nil` resets the engine to the
    /// current macOS system default input.
    ///
    /// Callers must invoke this before `start()` and after `installTap()`
    /// only if the tap format is re-read afterwards; in practice
    /// `AVAudioCaptureService` reads the input format once per start, so
    /// the current ordering (apply → installTap → start) is correct.
    internal func applyInputDevice(uid: String?) throws {
        try applyInputDeviceImpl(uid)
    }

    private let inputFormatProvider: () -> AVAudioFormat
    private let installTapImpl: (@escaping @Sendable (AVAudioPCMBuffer, AVAudioTime) -> Void) throws -> Void
    private let removeTapImpl: () -> Void
    private let prepareImpl: () -> Void
    private let startImpl: () throws -> Void
    private let stopImpl: () -> Void
    private let resetImpl: () -> Void
    private let applyInputDeviceImpl: (String?) throws -> Void
}

// MARK: - Live CoreAudio plumbing

extension AudioEngineDriver {
    /// Resolve the `AudioDeviceID` for a given `uid` (if any), then point the
    /// engine's input audio unit at it via
    /// `kAudioOutputUnitProperty_CurrentDevice`. `nil` uid → look up the
    /// current system default input device. A stored-but-missing device (e.g.
    /// the user unplugged the USB mic since they selected it) is NOT an
    /// error: we leave the current default in place and log a warning so
    /// recording still starts.
    fileprivate static func applyInputDeviceLive(
        uid: String?,
        inputNode: AVAudioInputNode
    ) throws {
        let targetDeviceID: AudioDeviceID?
        if let uid {
            if let resolved = audioDeviceID(forUID: uid) {
                targetDeviceID = resolved
            } else {
                // Persisted selection no longer enumerates — don't block
                // recording; fall through to the macOS system default.
                print("[PersonalScribeAudio] Selected input device UID \(uid) not found; using system default")
                return
            }
        } else {
            targetDeviceID = systemDefaultInputDeviceID()
        }

        guard var deviceID = targetDeviceID else {
            // No system-default device resolvable either — leave engine alone.
            return
        }

        guard let audioUnit = inputNode.audioUnit else {
            throw PersonalScribeAudioDeviceError.missingInputAudioUnit
        }

        let status = AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &deviceID,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )
        if status != noErr {
            throw PersonalScribeAudioDeviceError.audioUnitSetFailed(status: status)
        }
    }

    /// Enumerate CoreAudio devices and return the `AudioDeviceID` whose
    /// `kAudioDevicePropertyDeviceUID` matches `uid`. Returns `nil` when
    /// enumeration itself fails or when no device matches.
    fileprivate static func audioDeviceID(forUID uid: String) -> AudioDeviceID? {
        guard let devices = allAudioDevices() else { return nil }
        for deviceID in devices {
            if let deviceUID = deviceUID(for: deviceID), deviceUID == uid {
                return deviceID
            }
        }
        return nil
    }

    /// Read the current system default input device.
    fileprivate static func systemDefaultInputDeviceID() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID: AudioDeviceID = 0
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &deviceID
        )
        guard status == noErr, deviceID != 0 else { return nil }
        return deviceID
    }

    /// Return every `AudioDeviceID` registered with the system
    /// (`kAudioHardwarePropertyDevices`). Returns `nil` on CoreAudio API
    /// failure.
    private static func allAudioDevices() -> [AudioDeviceID]? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &dataSize
        )
        guard status == noErr, dataSize > 0 else { return nil }

        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)
        status = deviceIDs.withUnsafeMutableBufferPointer { buffer -> OSStatus in
            guard let base = buffer.baseAddress else { return kAudioHardwareUnspecifiedError }
            var readSize = dataSize
            return AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                0,
                nil,
                &readSize,
                base
            )
        }
        guard status == noErr else { return nil }
        return deviceIDs
    }

    /// Read `kAudioDevicePropertyDeviceUID` as a `String`. CoreAudio returns
    /// a retained `CFString` which we balance explicitly via
    /// `Unmanaged.takeRetainedValue()`.
    private static func deviceUID(for deviceID: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size = UInt32(MemoryLayout<CFString?>.size)
        var uidRef: Unmanaged<CFString>?
        let status = AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &size,
            &uidRef
        )
        guard status == noErr, let uidRef else { return nil }
        let cfString = uidRef.takeRetainedValue()
        return cfString as String
    }
}

/// Errors thrown by the live `applyInputDevice` path. `AVAudioCaptureService`
/// catches these and logs rather than failing the overall recording start —
/// falling back to the macOS system default is strictly better than blocking
/// the user from recording when a device-apply step fails.
internal enum PersonalScribeAudioDeviceError: Error, Equatable {
    case missingInputAudioUnit
    case audioUnitSetFailed(status: OSStatus)
}
