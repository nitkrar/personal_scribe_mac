import Foundation

public enum OfflineTranscriptionBatchModelPreference {
    public static let key = "OfflineTranscriptionBatchModelID"

    public static func resolve(
        from defaults: UserDefaults = .standard,
        activeFallback: () -> String
    ) -> String {
        if let stored = defaults.string(forKey: key) {
            return stored
        }

        let fallback = activeFallback()
        defaults.set(fallback, forKey: key)
        return fallback
    }

    public static func persist(
        _ value: String,
        to defaults: UserDefaults = .standard
    ) {
        defaults.set(value, forKey: key)
    }
}
