import Foundation

/// Errors thrown by `WorkflowModeValidator.validate(_:availableKinds:)`
/// (per #078 L15).
public enum WorkflowModeValidationError: Error, Equatable, Sendable {
    /// Recipe has zero processors. A pipeline with no work to do is
    /// not valid.
    case emptyProcessors

    /// Recipe declares a streaming transcriber processor but its
    /// `pipelineShape` is `.batch`, or vice-versa.
    case streamingShapeMismatch(processorKind: ModelKind, declaredShape: PipelineShape)

    /// Recipe references a `ModelKind` that is not currently available
    /// in `ActiveModelService` (no active descriptor for that kind, or
    /// the kind is gated off).
    case kindUnavailable(ModelKind)

    /// `.diarizedTurns(transcriberKind:)` was given a non-ASR kind.
    case diarizedTurnsRequiresAsrTranscriberKind(provided: ModelKind)

    /// Recipe's `pipelineShape == .streaming` but the processors list
    /// does not contain exactly one streaming-transcriber processor.
    case streamingShapeRequiresExactlyOneStreamingProcessor(count: Int)
}
