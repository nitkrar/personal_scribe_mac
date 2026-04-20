import Foundation

public enum AppBrand {
    public static let displayName = "Ninimma"
    public static let bundleIdentifier = "com.nitkrar.personal_scribe"
    public static let logSubsystem = bundleIdentifier
    public static let websiteURL: URL? = nil
    public static let privacyURL: URL? = nil
    public static let termsURL: URL? = nil

    /// One-line brand tagline shown directly under the app name in the About card.
    public static let tagline = "Your words, pressed into permanence."

    /// Short origin story for the About card — scribe/goddess role only.
    /// Full mythology: https://mythlok.com/ninimma/
    public static let originStory = "Ninimma was the divine scribe of the Sumerian gods — keeper of the clay tablet, guardian of celestial decrees. Her name means Lady of the Clay Tablet."
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
