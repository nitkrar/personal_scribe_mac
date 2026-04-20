import Foundation

/// Value-type description of a system audio input device, surfaced to
/// the menu-bar UI so it can render a "Microphone" submenu listing
/// available devices with a checkmark on the current selection.
///
/// `id` is opaque and stable across launches — on Apple platforms it is
/// sourced from `AVCaptureDevice.uniqueID` — and is persisted under
/// `UserDefaults` key `"SelectedAudioInputDeviceID"` by the default
/// `AudioInputDeviceProviding` implementation in `PersonalScribeAudio`.
/// `name` is a human-readable display name (localized by the OS).
///
/// Reference: `plans/App UI design/Manus_Final_Bundle_Prompt.md` §2
/// (Menu Bar Polish — Microphone submenu, M5.3).
public struct AudioInputDevice: Identifiable, Sendable, Equatable {
    /// Stable identifier for this device. Opaque to callers; the only
    /// meaningful operation is equality comparison against other
    /// `AudioInputDevice.id` values (e.g. the persisted selection).
    public let id: String

    /// Human-readable display name (e.g. `"MacBook Pro Microphone"`).
    /// Already localized by the OS where applicable.
    public let name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

/// Source of available audio input devices + persisted selection.
///
/// Injected into the AppKit status-item controller so the menu-bar
/// layer stays independent of AVFoundation and therefore unit-testable.
/// Concrete implementation in `PersonalScribeAudio`:
/// `AVFoundationInputDeviceProvider` uses
/// `AVCaptureDevice.DiscoverySession` for enumeration and persists the
/// selection under `UserDefaults` key `"SelectedAudioInputDeviceID"`.
///
/// Callers are expected to re-query `availableDevices()` on each menu
/// open so that hotplug/unplug events are reflected the next time the
/// user clicks the status item — no observer plumbing required.
public protocol AudioInputDeviceProviding: AnyObject, Sendable {
    /// Snapshot of currently-visible input devices. Re-query on each
    /// menu open to pick up hotplug changes. Returning an empty array
    /// is valid (e.g. no hardware yet) — the status-item controller
    /// omits the Microphone submenu entirely in that case.
    func availableDevices() -> [AudioInputDevice]

    /// Device ID the user has selected, or `nil` to use the macOS
    /// system default. Never returns a stale value for a device that
    /// has since disappeared from `availableDevices()` — callers must
    /// still defend against that when rendering the current selection.
    var selectedDeviceID: String? { get }

    /// Persist a new selection. Passing `nil` clears the preference
    /// and the next capture session falls back to the macOS system
    /// default input device.
    func selectDevice(id: String?)
}
