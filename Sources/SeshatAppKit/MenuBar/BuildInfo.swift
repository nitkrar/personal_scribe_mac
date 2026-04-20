import Foundation
import SeshatCore

struct BuildInfo: Equatable, Sendable {
    let version: String
    let buildNumber: String
    let shortSHA: String

    static var current: BuildInfo {
        BuildInfo(
            version: AppBrand.version,
            buildNumber: AppBrand.buildNumber,
            shortSHA: resolvedShortSHA(in: Bundle.main.infoDictionary ?? [:])
        )
    }

    // Temporary Stage 3 bridge so existing tests can still inject bundle
    // metadata while runtime version/build ownership stays in AppBrand.
    init(infoDictionary: [String: Any]) {
        self.init(
            version: Self.bridgeResolvedValue(
                forKeyComponents: ["CFBundle", "ShortVersionString"],
                fallback: "dev",
                in: infoDictionary
            ),
            buildNumber: Self.bridgeResolvedValue(
                forKeyComponents: ["CFBundle", "Version"],
                fallback: "dev",
                in: infoDictionary
            ),
            shortSHA: Self.resolvedShortSHA(in: infoDictionary)
        )
    }

    var displayString: String {
        "\(AppBrand.displayName) \(version) · \(shortSHA)"
    }

    private init(version: String, buildNumber: String, shortSHA: String) {
        self.version = version
        self.buildNumber = buildNumber
        self.shortSHA = shortSHA
    }

    private static func bridgeResolvedValue(
        forKeyComponents keyComponents: [String],
        fallback: String,
        in infoDictionary: [String: Any]
    ) -> String {
        let key = keyComponents.joined()
        guard
            let value = (infoDictionary[key] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
            value.isEmpty == false
        else {
            return fallback
        }

        return value
    }

    private static func resolvedShortSHA(in infoDictionary: [String: Any]) -> String {
        let sha = ((infoDictionary["SeshatGitSHA"] as? String) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return sha.isEmpty ? "unknown" : String(sha.prefix(7))
    }
}
