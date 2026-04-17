import Foundation

public enum SeshatError: Error, Sendable, Equatable {
    case micPermissionDenied
    case audioEngineFailure
    case resampleFailure
    case modelLoadFailure
    case transcriptionFailure
    case modelDownloadFailure
    case cancelled
    case invalidState
}

extension SeshatError: LocalizedError {
    public var errorDescription: String? { nil }
    public var failureReason: String? { nil }
    public var recoverySuggestion: String? { nil }
}
