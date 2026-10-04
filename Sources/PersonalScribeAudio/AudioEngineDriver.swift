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
        applyInputDevice: @escaping (String?) throws -> Void = { _ in },
        observeConfigurationChanges: @escaping (@escaping @Sendable () -> Void) -> Void = { _ in },
        isRunning: @escaping () -> Bool = { false }
    ) {
        self.inputFormatProvider = inputFormatProvider
        self.installTapImpl = installTap
        self.removeTapImpl = removeTap
        self.prepareImpl = prepare
        self.startImpl = start
        self.stopImpl = stop
        self.resetImpl = reset
        self.applyInputDeviceImpl = applyInputDevice
        self.observeConfigurationChangesImpl = observeConfigurationChanges
        self.isRunningImpl = isRunning
    }

    internal static func live() -> AudioEngineDriver {
        let live = LiveEngine()

        return AudioEngineDriver(
            // The hardware format; `outputFormat(forBus:)` can lag a device
            // change, and a tap at a stale rate fails with -10868.
            inputFormatProvider: { live.engine.inputNode.inputFormat(forBus: 0) },
            installTap: { handler in
                // A leftover tap or a format that doesn't match the hardware
                // makes installTap raise an uncatchable ObjC exception.
                let inputNode = live.engine.inputNode
                inputNode.removeTap(onBus: 0)
                inputNode.installTap(onBus: 0, bufferSize: 4_096, format: inputNode.inputFormat(forBus: 0)) { buffer, when in
                    handler(buffer, when)
                }
            },
            removeTap: {
                live.engine.inputNode.removeTap(onBus: 0)
            },
            prepare: {
                live.engine.prepare()
            },
            start: {
                try live.engine.start()
            },
            stop: {
                live.engine.stop()
            },
            reset: {
                live.engine.reset()
            },
            applyInputDevice: { uid in
                // Without a connected selection the engine must follow the
                // system default itself: a pinned device isn't tracked through
                // format or device changes. Unpinning needs a fresh engine.
                if let uid, try AudioEngineDriver.pinInputDevice(uid: uid, inputNode: live.engine.inputNode) {
                    live.isPinned = true
                } else if live.isPinned {
                    live.rebuild()
                }
            },
            observeConfigurationChanges: { handler in
                live.setConfigurationChangeHandler(handler)
            },
            isRunning: {
                live.engine.isRunning
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
    internal func observeConfigurationChanges(_ handler: @escaping @Sendable () -> Void) {
        observeConfigurationChangesImpl(handler)
    }
    internal var isRunning: Bool { isRunningImpl() }

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
    private let observeConfigurationChangesImpl: (@escaping @Sendable () -> Void) -> Void
    private let isRunningImpl: () -> Bool
}

// MARK: - Live CoreAudio plumbing

extension AudioEngineDriver {
    /// Points the engine's input at the device with `uid`. Returns false
    /// when that device isn't connected, so the caller falls back to the
    /// system default.
    fileprivate static func pinInputDevice(
        uid: String,
        inputNode: AVAudioInputNode
    ) throws -> Bool {
        guard var deviceID = audioDeviceID(forUID: uid) else {
            return false
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
        return true
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

/// Holds the current live engine and keeps the configuration-change
/// observer attached to whichever engine is current.
private final class LiveEngine: @unchecked Sendable {
    // Safe: mutated only from the owning AVAudioCaptureService actor.
    private(set) var engine = AVAudioEngine()
    var isPinned = false
    private var configurationChangeHandler: (@Sendable () -> Void)?
    private var observer: NSObjectProtocol?

    func setConfigurationChangeHandler(_ handler: @escaping @Sendable () -> Void) {
        configurationChangeHandler = handler
        observeCurrentEngine()
    }

    func rebuild() {
        engine.stop()
        engine = AVAudioEngine()
        isPinned = false
        observeCurrentEngine()
    }

    private func observeCurrentEngine() {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
        guard let handler = configurationChangeHandler else { return }
        // Posted when the input device disappears or changes format.
        observer = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: nil
        ) { _ in handler() }
    }
}
