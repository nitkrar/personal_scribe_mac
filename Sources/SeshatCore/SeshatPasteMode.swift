import Foundation

/// User-selectable transcript delivery mode.
///
/// Stored in `UserDefaults` at `SeshatPasteMode`. The default remains
/// `.pasteAtCursor` so existing behaviour is preserved until a user
/// explicitly opts into clipboard-only delivery.
public enum SeshatPasteMode: String, CaseIterable, Sendable, Equatable {
    case pasteAtCursor = "paste-at-cursor"
    case clipboardOnly = "clipboard-only"

    public static let `default`: SeshatPasteMode = .pasteAtCursor
    public static let userDefaultsKey = "SeshatPasteMode"

    public static func resolve(from defaults: UserDefaults = .standard) -> SeshatPasteMode {
        guard
            let raw = defaults.string(forKey: userDefaultsKey),
            let mode = SeshatPasteMode(rawValue: raw)
        else {
            return .default
        }
        return mode
    }

    public func persist(to defaults: UserDefaults = .standard) {
        defaults.set(rawValue, forKey: Self.userDefaultsKey)
    }
}
