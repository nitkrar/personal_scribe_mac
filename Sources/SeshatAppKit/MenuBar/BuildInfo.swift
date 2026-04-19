import Foundation
import SeshatCore

struct BuildInfo: Equatable, Sendable {
    let version: String
    let shortSHA: String

    static var current: BuildInfo {
        BuildInfo(infoDictionary: Bundle.main.infoDictionary ?? [:])
    }

    init(infoDictionary: [String: Any]) {
        let version = (infoDictionary["CFBundleShortVersionString"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        self.version = (version?.isEmpty == false) ? version! : "dev"

        let sha = ((infoDictionary["SeshatGitSHA"] as? String) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        self.shortSHA = sha.isEmpty ? "unknown" : String(sha.prefix(7))
    }

    var displayString: String {
        "\(AppBrand.displayName) \(version) · \(shortSHA)"
    }
}
