import PersonalScribeCore

public protocol SessionPipelining: Actor, Sendable {
    func toggleCapture() async
    /// Start a capture session in `.holdRecording`. Publishes the state
    /// transition eagerly (before awaiting `capture.start()`) so a
    /// concurrent hold-release routed through `toggleCapture()` observes
    /// `.holdRecording` and stops instead of silently no-opping on
    /// `.idle`. See `#071`.
    func startHoldCapture() async
    /// True-discard an active capture. Stops the audio engine, drops the
    /// buffered audio, and transitions directly to `.idle` — no
    /// transcription, no output delivery. No-op from any non-active
    /// state. See `#002`.
    func cancelCapture() async
    /// Resume the last cancelled capture (kept while the Cancel Card is
    /// up): capture again, appending to its audio, so stop transcribes
    /// one recording. No-op if nothing is resumable.
    func resumeCancelledCapture() async
    /// Drop the cancelled capture's audio (Cancel Card closed).
    func discardCancelledCapture() async
    func prepareTranscriber() async throws
    func snapshot() -> SessionSnapshot
    func snapshotStream() -> AsyncStream<SessionSnapshot>
    func audioLevelStream() -> AsyncStream<Float>
}
