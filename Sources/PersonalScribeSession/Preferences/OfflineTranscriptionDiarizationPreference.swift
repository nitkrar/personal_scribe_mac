import Foundation

public enum OfflineTranscriptionDiarizationPreference {
    public static let key = "OfflineTranscriptionDiarizationEnabled"
    public static let `default` = false

    public static func resolve(from defaults: UserDefaults = .standard) -> Bool {
        guard defaults.object(forKey: key) != nil else {
            return `default`
        }
        return defaults.bool(forKey: key)
    }

    public static func persist(
        _ value: Bool,
        to defaults: UserDefaults = .standard
    ) {
        defaults.set(value, forKey: key)
    }
}
