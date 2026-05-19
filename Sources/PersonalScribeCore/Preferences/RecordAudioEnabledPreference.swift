import Foundation

public enum RecordAudioEnabledPreference {
    public static let key = "RecordAudioEnabled"
    public static let `default` = true

    public static func resolve(from defaults: UserDefaults = .standard) -> Bool {
        guard defaults.object(forKey: key) != nil else {
            return `default`
        }
        return defaults.bool(forKey: key)
    }

    public static func persist(_ value: Bool, to defaults: UserDefaults = .standard) {
        defaults.set(value, forKey: key)
    }
}
