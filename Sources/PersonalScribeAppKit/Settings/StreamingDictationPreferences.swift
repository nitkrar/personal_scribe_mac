import Foundation
import PersonalScribeCore

public enum StreamingLiveCardEnabledPreference {
    public static let userDefaultsKey = PreferenceKeys.streamingLiveCardEnabled.key
    public static let `default` = PreferenceKeys.streamingLiveCardEnabled.default

    public static func resolve(from defaults: UserDefaults = .standard) -> Bool {
        guard defaults.object(forKey: userDefaultsKey) != nil else {
            return `default`
        }
        return defaults.bool(forKey: userDefaultsKey)
    }

    public static func persist(_ value: Bool, to defaults: UserDefaults = .standard) {
        defaults.set(value, forKey: userDefaultsKey)
    }
}

public enum StreamingLiveCursorEnabledPreference {
    public static let userDefaultsKey = PreferenceKeys.streamingLiveCursorEnabled.key
    public static let `default` = PreferenceKeys.streamingLiveCursorEnabled.default

    public static func resolve(from defaults: UserDefaults = .standard) -> Bool {
        guard defaults.object(forKey: userDefaultsKey) != nil else {
            return `default`
        }
        return defaults.bool(forKey: userDefaultsKey)
    }

    public static func persist(_ value: Bool, to defaults: UserDefaults = .standard) {
        defaults.set(value, forKey: userDefaultsKey)
    }
}

public enum StreamingSecondPassEnabledPreference {
    public static let userDefaultsKey = PreferenceKeys.streamingSecondPassEnabled.key
    public static let `default` = PreferenceKeys.streamingSecondPassEnabled.default

    public static func resolve(from defaults: UserDefaults = .standard) -> Bool {
        guard defaults.object(forKey: userDefaultsKey) != nil else {
            return `default`
        }
        return defaults.bool(forKey: userDefaultsKey)
    }

    public static func persist(_ value: Bool, to defaults: UserDefaults = .standard) {
        defaults.set(value, forKey: userDefaultsKey)
    }
}

public enum StreamingCardOverflowMode: String, CaseIterable, Codable, Sendable {
    case tailPinnedHeadEllipsis
    case marquee
    case wordByWordFade

    public var displayName: String {
        switch self {
        case .tailPinnedHeadEllipsis:
            return "Tail-pinned head ellipsis"
        case .marquee:
            return "Marquee"
        case .wordByWordFade:
            return "Word-by-word fade"
        }
    }
}

public enum StreamingCardOverflowModePreference {
    public static let userDefaultsKey = "StreamingCardOverflowMode"
    public static let `default`: StreamingCardOverflowMode = .tailPinnedHeadEllipsis

    public static func resolve(
        from defaults: UserDefaults = .standard
    ) -> StreamingCardOverflowMode {
        Preference<StreamingCardOverflowMode>(
            key: userDefaultsKey,
            default: `default`,
            defaults: defaults
        ).resolve()
    }

    public static func persist(
        _ value: StreamingCardOverflowMode,
        to defaults: UserDefaults = .standard
    ) {
        Preference<StreamingCardOverflowMode>(
            key: userDefaultsKey,
            default: `default`,
            defaults: defaults
        ).persist(value)
    }
}
