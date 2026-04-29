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

    /// Apply the resolved per-session sensitivity preset before the
    /// next `diarize(stream:)` call. Default no-op; real adapters
    /// translate the preset into vendor-specific tuning knobs (for
    /// FluidAudio: `OfflineDiarizerConfig.clustering.threshold` +
    /// `embedding.minSegmentDurationSeconds`).
    ///
    /// Called by the fusion processor at session start with the
    /// recipe-resolved sensitivity (per-mode override winning over
    /// the global preference).
    func applySensitivity(_ sensitivity: SpeakerSeparationSensitivity) async
}

extension SpeakerDiarizer {
    /// Default no-op so test stubs and future diarizer adapters can
    /// opt out of sensitivity tuning when their underlying engine
    /// doesn't expose equivalent knobs.
    public func applySensitivity(_ sensitivity: SpeakerSeparationSensitivity) async {
        // No-op default.
    }
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
