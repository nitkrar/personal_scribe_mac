import AppKit
import Foundation

/// Persisted recording-toggle hotkey configuration.
///
/// Stored in `UserDefaults` at `RecordingHotkey`. The default remains
/// the current shipping behaviour: double-tap right option with no extra
/// modifiers.
public struct HotkeyPreference: Codable, Sendable, Equatable {
    public let keyCode: UInt16
    public let tapCount: Int
    public let modifiers: NSEvent.ModifierFlags.RawValue

    public static let userDefaultsKey = "RecordingHotkey"
    public static let `default` = HotkeyPreference(
        keyCode: 61,
        tapCount: 2,
        modifiers: 0
    )

    public init(
        keyCode: UInt16,
        tapCount: Int = 2,
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
