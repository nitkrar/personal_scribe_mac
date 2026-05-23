import Foundation

public enum AudioRecordingRetentionDaysPreference {
    public static let userDefaultsKey = "AudioRecordingRetentionDays"
    public static let allowedValues = [0, 1, 7, 14, 30]
    public static let `default` = 7

    public static func preference(defaults: UserDefaults = .standard) -> Preference<Int> {
        Preference(key: userDefaultsKey, default: `default`, defaults: defaults)
    }

    public static func resolve(from defaults: UserDefaults = .standard) -> Int {
        sanitized(preference(defaults: defaults).resolve())
    }

    public static func persist(_ value: Int, to defaults: UserDefaults = .standard) {
        preference(defaults: defaults).persist(sanitized(value))
    }

    public static func sanitized(_ value: Int) -> Int {
        guard let nearest = allowedValues.min(by: { lhs, rhs in
            let lhsDistance = abs(lhs - value)
            let rhsDistance = abs(rhs - value)
            if lhsDistance == rhsDistance {
                return lhs < rhs
            }
            return lhsDistance < rhsDistance
        }) else {
            return `default`
        }

        return nearest
    }
}
