import Foundation

public enum AppBrand {
    public static let displayName = "Seshat"
    public static let bundleIdentifier = "com.nitkrar.seshat"
    public static let logSubsystem = bundleIdentifier
    public static let websiteURL: URL? = nil
    public static let privacyURL: URL? = nil
    public static let termsURL: URL? = nil
    public static let version = resolvedVersion(in: Bundle.main.infoDictionary ?? [:])
    public static let buildNumber = resolvedBuildNumber(in: Bundle.main.infoDictionary ?? [:])

    static func resolvedVersion(in infoDictionary: [String: Any]) -> String {
        resolvedInfoValue(forKey: "CFBundleShortVersionString", fallback: "dev", in: infoDictionary)
    }

    static func resolvedBuildNumber(in infoDictionary: [String: Any]) -> String {
        resolvedInfoValue(forKey: "CFBundleVersion", fallback: "dev", in: infoDictionary)
    }

    private static func resolvedInfoValue(
        forKey key: String,
        fallback: String,
        in infoDictionary: [String: Any]
    ) -> String {
        guard
            let value = (infoDictionary[key] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
            value.isEmpty == false
        else {
            return fallback
        }

        return value
    }
}
