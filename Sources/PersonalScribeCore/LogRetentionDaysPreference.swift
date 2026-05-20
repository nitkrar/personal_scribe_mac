import Foundation

public enum LogRetentionDaysPreference {
    public static let userDefaultsKey = "LogRetentionDays"
    public static let `default` = 14
    public static let minimum = 0
    public static let maximum = 90

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
        min(max(value, minimum), maximum)
    }
}
