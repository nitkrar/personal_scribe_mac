import AppKit
import Foundation
import PersonalScribeCore

/// One entry from `~/Library/Preferences/com.apple.symbolichotkeys.plist`.
///
/// The plist stores modifier flags as Cocoa `NSEvent.ModifierFlags`
/// raw values (cmd = 0x100000, option = 0x80000, ctrl = 0x40000,
/// shift = 0x20000 — same region as `.deviceIndependentFlagsMask`).
/// We filter down to the four chord modifiers we care about before
/// comparing against the user's captured preference.
struct SystemHotkey: Equatable {
    let identifier: Int
    let keyCode: UInt16
    let modifiers: NSEvent.ModifierFlags
    let isEnabled: Bool
    let displayName: String
}

/// Result of comparing a user-captured `HotkeyPreference` against the
/// system's assigned shortcuts. `nil` = no collision.
enum SystemHotkeyCollision: Equatable {
    case enabled(name: String)
    case disabled(name: String)
}

enum SystemHotkeyRegistry {
    /// The sentinel keyCode macOS writes when a symbolic hotkey has no
    /// keyboard binding assigned. Entries with this keyCode are skipped.
    private static let unassignedKeyCodeSentinel: UInt16 = 0xFFFF

    private static let chordModifierMask: NSEvent.ModifierFlags = [
        .command, .option, .control, .shift,
    ]

    static let defaultPlistURL: URL = URL(
        fileURLWithPath: NSHomeDirectory()
    ).appendingPathComponent("Library/Preferences/com.apple.symbolichotkeys.plist")

    /// Load the user's current system hotkey bindings. Missing /
    /// unreadable / malformed plist yields an empty set — we fail open,
    /// never block the user from capturing a shortcut because we can't
    /// read the plist.
    static func load(from url: URL = defaultPlistURL) -> [SystemHotkey] {
        guard
            let data = try? Data(contentsOf: url),
            let root = (try? PropertyListSerialization.propertyList(
                from: data,
                format: nil
            )) as? [String: Any]
        else {
            return []
        }

        return parse(root)
    }

    /// Pure extraction path — exposed for fixture-driven tests that build
    /// a plist dictionary directly without touching disk.
    static func parse(_ root: [String: Any]) -> [SystemHotkey] {
        guard let hotkeys = root["AppleSymbolicHotKeys"] as? [String: Any] else {
            return []
        }

        var result: [SystemHotkey] = []
        for (key, value) in hotkeys {
            guard
                let identifier = Int(key),
                let entry = value as? [String: Any],
                let enabled = entry["enabled"] as? Bool,
                let wrapper = entry["value"] as? [String: Any],
                let type = wrapper["type"] as? String, type == "standard",
                let parameters = wrapper["parameters"] as? [Any],
                parameters.count >= 3,
                let rawKeyCode = parameters[1] as? Int,
                let rawModifiers = parameters[2] as? Int
            else {
                continue
            }

            let keyCode = UInt16(truncatingIfNeeded: rawKeyCode)
            if keyCode == unassignedKeyCodeSentinel {
                continue
            }

            let cocoa = NSEvent.ModifierFlags(rawValue: UInt(rawModifiers))
                .intersection(chordModifierMask)

            result.append(SystemHotkey(
                identifier: identifier,
                keyCode: keyCode,
                modifiers: cocoa,
                isEnabled: enabled,
                displayName: SystemHotkeyNames.name(for: identifier)
            ))
        }

        return result
    }

    /// Return a collision if `preference` overlaps a system hotkey,
    /// else `nil`. Enabled collisions are hard rejections; disabled
    /// collisions become warnings so the user can still bind over them
    /// but knows re-enabling the system shortcut will conflict.
    static func collision(
        for preference: HotkeyPreference,
        against hotkeys: [SystemHotkey]
    ) -> SystemHotkeyCollision? {
        let targetModifiers = preference.modifierFlags.intersection(chordModifierMask)

        for hotkey in hotkeys
        where hotkey.keyCode == preference.keyCode && hotkey.modifiers == targetModifiers {
            return hotkey.isEnabled
                ? .enabled(name: hotkey.displayName)
                : .disabled(name: hotkey.displayName)
        }
        return nil
    }
}

/// Human-readable names for common AppleSymbolicHotKeys identifiers.
/// Coverage is best-effort; unknown identifiers fall back to a generic
/// label. IDs and defaults sourced from
/// System Settings → Keyboard → Keyboard Shortcuts.
enum SystemHotkeyNames {
    private static let names: [Int: String] = [
        7: "Move focus to the menu bar",
        8: "Move focus to the Dock",
        9: "Move focus to active / next window",
        10: "Move focus to window toolbar",
        11: "Move focus to floating window",
        12: "Toggle keyboard access",
        13: "Move focus to next window in application",
        14: "Move focus to window drawer",
        15: "Move focus to status menus",
        27: "Move focus to next display",
        28: "Save picture of screen as a file",
        29: "Copy picture of screen to clipboard",
        30: "Save picture of selected area as a file",
        31: "Copy picture of selected area to clipboard",
        32: "Mission Control",
        33: "Application windows",
        34: "Show desktop",
        36: "Show Dashboard",
        52: "Toggle Dock hiding",
        60: "Select previous input source",
        61: "Select next input source in menu",
        62: "Select next input source",
        64: "Spotlight",
        65: "Spotlight Finder window",
        75: "Look up",
        79: "Move to space left",
        80: "Move to space left (alternate)",
        81: "Move to space right",
        82: "Move to space right (alternate)",
        98: "Help",
        118: "Switch to Desktop 1",
        119: "Switch to Desktop 2",
        120: "Switch to Desktop 3",
        121: "Switch to Desktop 4",
        160: "Show Launchpad",
        162: "Show Notification Center",
        163: "Turn Do Not Disturb on/off",
        184: "Screenshot and recording options",
        190: "Quick Note",
    ]

    static func name(for identifier: Int) -> String {
        names[identifier] ?? "a system shortcut (id \(identifier))"
    }
}
