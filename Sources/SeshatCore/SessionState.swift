public enum SessionState: Sendable, Equatable {
    case idle
    case recording
    case transcribing
    case error(SeshatError)
}
