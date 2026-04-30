import Foundation

public enum DiagnosticsLevel: String, Codable, CaseIterable, Sendable, Equatable, Comparable {
    case debug
    case info
    case notice
    case error

    private var sortOrder: Int {
        switch self {
        case .debug:
            0
        case .info:
            1
        case .notice:
            2
        case .error:
            3
        }
    }

    public static func < (lhs: DiagnosticsLevel, rhs: DiagnosticsLevel) -> Bool {
        lhs.sortOrder < rhs.sortOrder
    }
}
