import Foundation
import PersonalScribeCore

public enum StreamingLiveCardEnabledPreference: StoredPreference {
    public static let setting = PreferenceKeys.streamingLiveCardEnabled
}

public enum StreamingLiveCursorEnabledPreference: StoredPreference {
    public static let setting = PreferenceKeys.streamingLiveCursorEnabled
}

public enum StreamingSecondPassEnabledPreference: StoredPreference {
    public static let setting = PreferenceKeys.streamingSecondPassEnabled
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

public enum StreamingCardOverflowModePreference: StoredPreference {
    public static let setting = SettingKey<StreamingCardOverflowMode>(
        key: "StreamingCardOverflowMode",
        default: .tailPinnedHeadEllipsis
    )
}
