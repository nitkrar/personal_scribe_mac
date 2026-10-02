import Foundation

/// How long the Cancel Card (shown after Esc / ✕) stays up offering
/// Resume. When it closes, the cancelled recording's audio is discarded.
/// Range 1–10s, default 3s.
public struct CancelCardDuration: Sendable, Equatable {
    public let seconds: TimeInterval

    public static let `default`: CancelCardDuration = .init(seconds: 3.0)
    public static let userDefaultsKey = "CancelCardSeconds"

    public static let minimumSeconds: TimeInterval = 1.0
    public static let maximumSeconds: TimeInterval = 10.0

    public init(seconds: TimeInterval) {
        self.seconds = seconds
    }

    public static func resolve(from defaults: UserDefaults = .standard) -> CancelCardDuration {
        let stored = Preference(key: userDefaultsKey, default: Self.default.seconds, defaults: defaults).resolve()
        return CancelCardDuration(seconds: sanitized(stored))
    }

    public static func persist(to defaults: UserDefaults = .standard, _ duration: CancelCardDuration) {
        Preference(key: userDefaultsKey, default: Self.default.seconds, defaults: defaults)
            .persist(sanitized(duration.seconds))
    }

    private static func sanitized(_ seconds: TimeInterval) -> TimeInterval {
        guard seconds.isFinite else { return `default`.seconds }
        return max(minimumSeconds, min(seconds, maximumSeconds))
    }
}
