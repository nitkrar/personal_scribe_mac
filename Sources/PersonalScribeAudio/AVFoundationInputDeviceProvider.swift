import AVFoundation
import Foundation
import PersonalScribeCore

/// Production `AudioInputDeviceProviding` conformer.
///
/// Enumeration uses `AVCaptureDevice.DiscoverySession` — cleaner than
/// Core Audio HAL for our single need (list + name + stable ID).
/// Selection persists under `UserDefaults` key
/// `"SelectedAudioInputDeviceID"` (unprefixed per project convention —
/// see `OnboardingCompleted`, `SeshatLogLevel` et al.).
///
/// This type does NOT apply the selection to the live capture engine —
/// `AVAudioCaptureService` still starts on the macOS system default
/// input at the time of writing. Wiring the selection into the engine
/// via `AudioUnitSetProperty(kAudioOutputUnitProperty_CurrentDevice)`
/// on `engine.inputNode.audioUnit` is a tracked M5.3 followup.
///
/// Reference: `plans/App UI design/Manus_Final_Bundle_Prompt.md` §2.
public final class AVFoundationInputDeviceProvider: AudioInputDeviceProviding, @unchecked Sendable {
    private let defaults: UserDefaults

    /// UserDefaults key. Unprefixed to match the rest of the codebase
    /// (`OnboardingCompleted`, `PillVisibilityMode`, …).
    static let userDefaultsKey = "SelectedAudioInputDeviceID"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func availableDevices() -> [AudioInputDevice] {
        // Package.swift pins `.macOS(.v14)` so the modern
        // `.microphone` / `.external` device types are always
        // available. `.unspecified` position returns both built-in
        // and external inputs in one list.
        let session = AVCaptureDevice.DiscoverySession(
            deviceTypes: Self.supportedDeviceTypes,
            mediaType: .audio,
            position: .unspecified
        )
        return session.devices.map { device in
            AudioInputDevice(id: device.uniqueID, name: device.localizedName)
        }
    }

    public var selectedDeviceID: String? {
        defaults.string(forKey: Self.userDefaultsKey)
    }

    public func selectDevice(id: String?) {
        if let id, !id.isEmpty {
            defaults.set(id, forKey: Self.userDefaultsKey)
        } else {
            defaults.removeObject(forKey: Self.userDefaultsKey)
        }
    }

    // MARK: - Device-type selection

    /// Device types we enumerate for the Microphone submenu. `.microphone`
    /// is the macOS 14+ replacement for the legacy `.builtInMicrophone`
    /// constant (it covers the built-in input); `.external` covers USB
    /// and similar peripherals. Together they match the set macOS shows
    /// in System Settings › Sound › Input.
    private static let supportedDeviceTypes: [AVCaptureDevice.DeviceType] = [
        .microphone,
        .external,
    ]
}

/// Default `AudioInputDeviceProviding` used when `AVAudioCaptureService` is
/// constructed without an explicit provider — always reports no selection so
/// the capture engine falls through to the macOS system default input.
///
/// Useful for tests and for the zero-argument convenience initializer that
/// predates M5.3. Production wiring in `AppComposition` passes a real
/// `AVFoundationInputDeviceProvider(defaults: .standard)` instead.
public final class NoOpAudioInputDeviceProvider: AudioInputDeviceProviding, @unchecked Sendable {
    public init() {}
    public func availableDevices() -> [AudioInputDevice] { [] }
    public var selectedDeviceID: String? { nil }
    public func selectDevice(id: String?) {}
}
