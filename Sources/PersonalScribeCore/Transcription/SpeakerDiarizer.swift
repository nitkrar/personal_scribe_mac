import Foundation

/// Speaker-diarization surface. Composes `ModelLifecycle` per L13.
/// Update-oriented event shape per L10 — one protocol carries both
/// streaming (LSEEND/Sortformer, separate ticket) and offline
/// (`OfflineDiarizerManager`, degenerate-streaming case) diarization,
/// matching FluidAudio's vendor-side unification.
///
/// The fusion processor (`DiarizedTurnTranscriptionProcessor`, #078.23)
/// consumes the event stream and slices audio per finalized turn per
/// L26.
public protocol SpeakerDiarizer: ModelLifecycle, Sendable {
    /// Run diarization over a stream of audio chunks. Returns a
    /// non-throwing `AsyncStream` because the diarizer's stream
    /// terminates with a `.terminal` event rather than throwing —
    /// errors (load failures, model crashes) surface via `prepare()`
    /// or are wrapped into the terminal event.
    func diarize(
        stream: AsyncThrowingStream<PCMBuffer, Error>
    ) -> AsyncStream<SpeakerDiarizationEvent>
}

extension SpeakerDiarizer {
    /// Batch convenience that wraps a single buffer in a one-element
    /// stream and delegates to `diarize(stream:)`. Lets callers that
    /// already have the full audio (e.g. post-recording offline
    /// diarization) skip the boilerplate of building an
    /// `AsyncThrowingStream`.
    public func diarize(_ audio: PCMBuffer) -> AsyncStream<SpeakerDiarizationEvent> {
        let single: AsyncThrowingStream<PCMBuffer, Error> = AsyncThrowingStream { continuation in
            continuation.yield(audio)
            continuation.finish()
        }
        return diarize(stream: single)
    }
}
