import Foundation

public enum UserFacingDiagnostic: Sendable, Equatable {
    case sessionError(
        mapped: PersonalScribeError,
        messageOverride: String? = nil,
        autoDismissAfter: TimeInterval = 4.0
    )
}
