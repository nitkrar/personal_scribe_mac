import AppKit
import Foundation

/// Persisted recording-toggle hotkey configuration.
///
/// Stored in `UserDefaults` at `RecordingHotkey`.
///
/// ## Default (pill UX spec §3, 2026-04-21)
/// `opt + /` (keyCode 44, modifier `.option`). Single-tap press-and-
/// release toggles recording; hold past 300 ms enters Hold-to-Record
/// with mic capture, release transcribes. Double-tap is an alias for
/// single-tap (debounced to fire once per 400 ms window).
///
/// ## Legacy `tapCount` field
/// Retained for Codable storage compatibility. `GlobalHotkeyMonitor`
/// now implements the tap / hold / double-tap-debounce state machine
/// uniformly for every hotkey, regardless of stored `tapCount`. New
/// code should pass `tapCount: 1` when constructing a preference; old
/// persisted values (`2` from the pre-spec right-Option default) still
/// decode, their `tapCount` is simply ignored by the monitor.
public struct HotkeyPreference: Codable, Sendable, Equatable {
    public let keyCode: UInt16
    public let tapCount: Int
    public let modifiers: NSEvent.ModifierFlags.RawValue

    public static let userDefaultsKey = "RecordingHotkey"
    /// keyCode 44 is `/` on a US keyboard. `.option.rawValue` in the
    /// deviceIndependentFlagsMask bit set is stored as an integer.
    public static let `default` = HotkeyPreference(
        keyCode: 44,
        tapCount: 1,
        modifiers: NSEvent.ModifierFlags.option.rawValue
    )

    public init(
        keyCode: UInt16,
        tapCount: Int = 1,
        modifiers: NSEvent.ModifierFlags.RawValue
    ) {
        self.keyCode = keyCode
        self.tapCount = tapCount
        self.modifiers = modifiers
    }

    public static func preference(defaults: UserDefaults = .standard) -> Preference<Self> {
        Preference(key: userDefaultsKey, default: .default, defaults: defaults)
    }

    public static func resolve(from defaults: UserDefaults = .standard) -> HotkeyPreference {
        let preference = preference(defaults: defaults).resolve()
        guard preference.isSupported else {
            return .default
        }
        return preference
    }

    public func persist(to defaults: UserDefaults = .standard) {
        Self.preference(defaults: defaults).persist(self)
    }

    public var modifierFlags: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: modifiers).intersection(.deviceIndependentFlagsMask)
    }

    private var isSupported: Bool {
        (1...2).contains(tapCount)
    }
}
