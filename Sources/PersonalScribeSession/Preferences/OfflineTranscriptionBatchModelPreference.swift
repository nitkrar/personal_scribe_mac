import Foundation
import PersonalScribeCore

public enum OfflineTranscriptionBatchModelPreference {
    public static let setting = SettingKey<String>(key: "OfflineTranscriptionBatchModelID", default: "")
    public static let key = setting.key

    public static func resolve(
        from defaults: UserDefaults = .standard,
        activeFallback: () -> String
    ) -> String {
        let stored = setting.resolve(from: defaults)
        if !stored.isEmpty {
            return stored
        }

        let fallback = activeFallback()
        setting.persist(fallback, to: defaults)
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
        setting.persist(value, to: defaults)
    }
}
