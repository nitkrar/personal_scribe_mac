import Foundation

/// Streaming ASR transcriber surface. Composes `ModelLifecycle` per
/// L13 / L9, exposes `capabilities` per L11, and consumes a stream
/// of `PCMBuffer` chunks emitting `StreamingTranscriptionEvent`s.
///
/// Today's only conformer (Phase D) is
/// `FluidAudioStreamingTranscriberAdapter` wrapping FluidAudio's
/// `StreamingEouAsrManager`. The adapter bridges the manager's
/// partial/EOU/finish callbacks to the
/// `AsyncThrowingStream<StreamingTranscriptionEvent, Error>` shape
/// declared here.
public protocol StreamingTranscriber: ModelLifecycle, Sendable {
    /// Capabilities surface — same shape as `Transcriber.capabilities`
    /// per L9 (three role protocols, no polymorphic unification, but
    /// each declares its own optional metadata story).
    var capabilities: TranscriberCapabilities { get }

    /// Consume a stream of audio chunks; emit partial / EOU /
    /// finalized events. Implementations are expected to have
    /// completed `prepare()` before being called. The returned
    /// stream terminates on stream end (with `.finalized`) or on
    /// failure (the throwing stream surfaces the error).
    func transcribe(
        stream: AsyncThrowingStream<PCMBuffer, Error>
    ) -> AsyncThrowingStream<StreamingTranscriptionEvent, Error>
}
