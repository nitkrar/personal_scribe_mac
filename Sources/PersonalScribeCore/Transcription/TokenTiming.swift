import Foundation

/// Per-token timing emitted by transcribers that advertise
/// `TranscriberCapabilities.providesTokenTimings`. Token (not word) is
/// the FluidAudio public-surface granularity per #078 L11 / the
/// 2026-04-25 fluidaudio-fusion investigation.
public struct TokenTiming: Sendable, Equatable {
    /// The decoded token text. May be a sub-word fragment depending
    /// on the model's vocabulary.
    public let token: String

    /// Token start offset relative to the input audio's start.
    public let start: Duration

    /// Token end offset relative to the input audio's start.
    public let end: Duration

    /// Optional per-token confidence in `[0, 1]`. Adapters that don't
    /// surface per-token confidence (only an overall score) leave
    /// this `nil`.
    public let confidence: Float?

    public init(
        token: String,
        start: Duration,
        end: Duration,
        confidence: Float? = nil
    ) {
        self.token = token
        self.start = start
        self.end = end
        self.confidence = confidence
    }
}
