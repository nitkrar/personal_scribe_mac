public enum PillVisibilityState: Sendable, Equatable {
    case hidden
    case idle
    case downloading(fractionCompleted: Double)
    case loading
    case recording
    case transcribing
    case done
    case error(message: String)
}
