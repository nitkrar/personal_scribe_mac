import Foundation

public struct PausedRecordingTimeout: Sendable, Equatable {
    public let minutes: TimeInterval

    public static let `default` = PausedRecordingTimeout(minutes: 5)
    public static let userDefaultsKey = "PausedRecordingTimeout"
    public static let minimumMinutes: TimeInterval = 1
    public static let maximumMinutes: TimeInterval = 30

    public init(minutes: TimeInterval) {
        self.minutes = minutes
    }

    public var duration: Duration {
        .seconds(minutes * 60)
    }

    public static func resolve(
        from defaults: UserDefaults = .standard
    ) -> PausedRecordingTimeout {
        let stored = Preference(
            key: userDefaultsKey,
            default: Self.default.minutes,
            defaults: defaults
        ).resolve()
        return PausedRecordingTimeout(minutes: sanitized(stored))
    }

    public static func persist(
        to defaults: UserDefaults = .standard,
        _ timeout: PausedRecordingTimeout
    ) {
        Preference(
            key: userDefaultsKey,
            default: Self.default.minutes,
            defaults: defaults
        ).persist(sanitized(timeout.minutes))
    }

    private static func sanitized(_ minutes: TimeInterval) -> TimeInterval {
        guard minutes.isFinite else { return Self.default.minutes }
        return max(minimumMinutes, min(minutes, maximumMinutes))
    }
}
