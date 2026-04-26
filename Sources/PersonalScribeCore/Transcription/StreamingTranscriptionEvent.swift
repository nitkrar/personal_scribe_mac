import Foundation

/// Events a `StreamingTranscriber` emits while processing an
/// audio stream. Mirrors FluidAudio's `StreamingEouAsrManager`
/// callback-driven shape (per the 2026-04-25 ASR-output-shapes
/// investigation): partial transcript revisions, end-of-utterance
/// snapshots, and a single terminal finalize.
public enum StreamingTranscriptionEvent: Sendable, Equatable {
    /// Best-effort live transcript that may be revised by a
    /// subsequent `.partial` or replaced by a `.endOfUtterance`.
    case partial(text: String)

    /// Adapter detected an end-of-utterance boundary and emits the
    /// stable transcript for that utterance. Further `.partial`
    /// events may follow if the stream continues.
    case endOfUtterance(text: String)

    /// Stream-level terminal event with the full final transcript
    /// rolled up across the session. Always the last event before
    /// the stream finishes.
    case finalized(TranscriptionResult)
}
