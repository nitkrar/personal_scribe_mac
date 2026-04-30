import Foundation

public enum ShowLiveDiagnosticsOverlayPreference {
    public static let userDefaultsKey = "ShowLiveDiagnosticsOverlay"
    public static let `default` = false

    public static func preference(defaults: UserDefaults = .standard) -> Preference<Bool> {
        Preference(key: userDefaultsKey, default: `default`, defaults: defaults)
    }

    public static func resolve(from defaults: UserDefaults = .standard) -> Bool {
        preference(defaults: defaults).resolve()
    }

    public static func persist(_ value: Bool, to defaults: UserDefaults = .standard) {
        preference(defaults: defaults).persist(value)
    }
}
