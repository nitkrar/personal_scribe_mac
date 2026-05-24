import Foundation
import PersonalScribeCore

public enum OfflineTranscriptionBatchModelPreference {
    public static let key = "OfflineTranscriptionBatchModelID"

    public static func resolve(
        from defaults: UserDefaults = .standard,
        activeFallback: () -> String
    ) -> String {
        if let stored = defaults.string(forKey: key), !stored.isEmpty {
            return stored
        }

        let fallback = activeFallback()
        defaults.set(fallback, forKey: key)
        return fallback
    }

    @MainActor
    public static func resolve(
        from defaults: UserDefaults = .standard,
        modelService: ActiveModelService
    ) -> String {
        resolve(from: defaults) {
            modelService.activeDescriptor(for: .asr)?.id
                ?? BuiltInModelCatalog.parakeetTDT06Bv2.id
        }
    }

    public static func persist(
        _ value: String,
        to defaults: UserDefaults = .standard
    ) {
        defaults.set(value, forKey: key)
    }
}
