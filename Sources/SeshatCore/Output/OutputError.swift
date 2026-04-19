public enum OutputError: Error, Equatable, Sendable {
    case clipboardWriteFailed
    case clipboardOnlyFallback
    case streamingTransportDecisionRequired
    case copyUnavailable
}
