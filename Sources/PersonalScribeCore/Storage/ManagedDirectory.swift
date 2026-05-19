import Foundation

public enum ManagedDirectory: String, CaseIterable, Sendable {
    case models
    case modes
    case recordings
    case db
    case logs
    case cache

    public var pathComponent: String {
        rawValue
    }
}
