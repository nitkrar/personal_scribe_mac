import AppKit
import PersonalScribeCore

/// Hotkeys Ninimma reserves for itself — cannot be rebound as the
/// recording toggle because the app uses them for distinct behaviors.
///
/// Today the only reserved binding is Escape (any modifier combination),
/// consumed by `EscapeKeyMonitor` for the discard / close-pill path.
/// New in-app hotkeys (e.g. mode cycling under #068, pause/resume under
/// #070) should append entries here so the recorder rejects them
/// consistently.
///
/// Matching rules:
/// * `keyCode` must match exactly.
/// * If `modifiers` is `nil`, matches any modifier combination for the
///   given keyCode (Esc with any chord is still reserved).
/// * Otherwise, modifiers must match exactly.
enum ReservedInAppHotkeys {
    struct Entry: Equatable {
        let keyCode: UInt16
        let modifiers: NSEvent.ModifierFlags?
        let reason: String
    }

    private static let escapeKeyCode: UInt16 = 53

    static let entries: [Entry] = [
        Entry(
            keyCode: escapeKeyCode,
            modifiers: nil,
            reason: "Escape is reserved to discard the active recording."
        )
    ]

    /// Returns the reservation reason if `preference` collides with an
    /// in-app hotkey, or `nil` if free.
    static func reservationReason(for preference: HotkeyPreference) -> String? {
        let preferenceModifiers = preference.modifierFlags

        for entry in entries where entry.keyCode == preference.keyCode {
            if let required = entry.modifiers {
                if preferenceModifiers == required {
                    return entry.reason
                }
            } else {
                return entry.reason
            }
        }

        return nil
    }
}
