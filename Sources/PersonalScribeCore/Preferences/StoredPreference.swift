import Foundation

/// A named preference whose key, default and storage all come from one `SettingKey`.
public protocol StoredPreference {
    associatedtype Value: Codable & Sendable
    static var setting: SettingKey<Value> { get }
}

extension StoredPreference {
    public static var userDefaultsKey: String { setting.key }
    public static var `default`: Value { setting.default }

    public static func resolve(from defaults: UserDefaults = .standard) -> Value {
        setting.resolve(from: defaults)
    }

    public static func persist(_ value: Value, to defaults: UserDefaults = .standard) {
        setting.persist(value, to: defaults)
    }
}
