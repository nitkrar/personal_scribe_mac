import AppKit
import Foundation

/// Persisted recording-toggle hotkey configuration.
///
/// Stored in `UserDefaults` at `SeshatRecordingHotkey`. The default remains
/// the current shipping behaviour: double-tap right option with no extra
/// modifiers.
public struct HotkeyPreference: Codable, Sendable, Equatable {
    public let keyCode: UInt16
    public let tapCount: Int
    public let modifiers: NSEvent.ModifierFlags.RawValue

    public static let userDefaultsKey = "SeshatRecordingHotkey"
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

    public static func resolve(from defaults: UserDefaults = .standard) -> HotkeyPreference {
        guard
            let data = defaults.data(forKey: userDefaultsKey),
            let preference = try? JSONDecoder().decode(HotkeyPreference.self, from: data),
            preference.isSupported
        else {
            return .default
        }
        return preference
    }

    public func persist(to defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(self) else {
            return
        }
        defaults.set(data, forKey: Self.userDefaultsKey)
    }

    public var modifierFlags: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: modifiers).intersection(.deviceIndependentFlagsMask)
    }

    private var isSupported: Bool {
        (1...2).contains(tapCount)
    }
}
