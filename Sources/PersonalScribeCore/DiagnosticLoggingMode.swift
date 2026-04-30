import Foundation

public enum DiagnosticLoggingMode: String, Codable, CaseIterable, Sendable, Equatable {
    case errorsOnly
    case verbose

    public static let userDefaultsKey = "DiagnosticLoggingMode"
    public static let `default`: DiagnosticLoggingMode = .errorsOnly

    public static func preference(defaults: UserDefaults = .standard) -> Preference<Self> {
        Preference(key: userDefaultsKey, default: .default, defaults: defaults)
    }

    public static func resolve(from defaults: UserDefaults = .standard) -> DiagnosticLoggingMode {
        preference(defaults: defaults).resolve()
    }

    public func persist(to defaults: UserDefaults = .standard) {
        Self.preference(defaults: defaults).persist(self)
    }

    public var minimumBufferedLevel: DiagnosticsLevel {
        switch self {
        case .errorsOnly:
            .error
        case .verbose:
            .debug
        }
    }
}
