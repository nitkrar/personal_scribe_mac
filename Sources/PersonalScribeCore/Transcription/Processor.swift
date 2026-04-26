import Foundation

/// Sum-typed processor output introduced in #078 Phase E. A processor
/// can yield one batch transcript, one streaming transcript event
/// stream, or one diarization event stream without relying on an
/// associated type.
public enum ProcessorOutput: Sendable {
    case text(TranscriptionResult)
    case streamingText(AsyncThrowingStream<StreamingTranscriptionEvent, Error>)
    case turns(AsyncStream<SpeakerDiarizationEvent>)
}

/// Unified processor role surface for components that consume audio
/// and optional prior processor outputs, then emit one of the
/// supported output modalities via `ProcessorOutput`.
public protocol Processor: ModelLifecycle, Sendable {
    func process(audio: PCMBuffer, priors: [ProcessorOutput]) async throws -> ProcessorOutput
}
