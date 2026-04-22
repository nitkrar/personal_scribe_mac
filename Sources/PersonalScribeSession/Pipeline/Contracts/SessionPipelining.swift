import PersonalScribeCore

public protocol SessionPipelining: Actor, Sendable {
    func toggleCapture() async
    /// Start a capture session in `.holdRecording`. Publishes the state
    /// transition eagerly (before awaiting `capture.start()`) so a
    /// concurrent hold-release routed through `toggleCapture()` observes
    /// `.holdRecording` and stops instead of silently no-opping on
    /// `.idle`. See `#071`.
    func startHoldCapture() async
    func prepareTranscriber() async throws
    func snapshot() -> PipelineSnapshot
    func snapshotStream() -> AsyncStream<PipelineSnapshot>
    func audioLevelStream() -> AsyncStream<Float>
    func modelDownloadProgress() -> AsyncStream<ModelDownloadProgress>
}
