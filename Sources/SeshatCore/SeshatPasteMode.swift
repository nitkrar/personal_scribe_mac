import Foundation

/// User-selectable transcript delivery mode.
///
/// Stored in `UserDefaults` at `PasteMode`. The default remains
/// `.pasteAtCursor` so existing behaviour is preserved until a user
/// explicitly opts into clipboard-only delivery.
public enum PasteMode: String, CaseIterable, Codable, Sendable, Equatable {
    case pasteAtCursor = "paste-at-cursor"
    case clipboardOnly = "clipboard-only"

    public static let `default`: Self = .pasteAtCursor
    public static let userDefaultsKey = "PasteMode"

    public static func preference(defaults: UserDefaults = .standard) -> Preference<Self> {
        Preference(key: userDefaultsKey, default: .default, defaults: defaults)
    }

    public static func resolve(from defaults: UserDefaults = .standard) -> Self {
        preference(defaults: defaults).resolve()
    }

    public func persist(to defaults: UserDefaults = .standard) {
        Self.preference(defaults: defaults).persist(self)
    }
}

public typealias SeshatPasteMode = PasteMode
