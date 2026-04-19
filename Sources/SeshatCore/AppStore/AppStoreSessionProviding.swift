public protocol AppStoreSessionProviding: Sendable {
    func stateStream() -> AsyncStream<SessionState>
    func modelDownloadProgress() -> AsyncStream<ModelDownloadProgress>
    func lastResult() -> TranscriptionResult?
}
