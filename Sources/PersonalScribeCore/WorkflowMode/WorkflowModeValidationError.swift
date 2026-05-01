import Foundation

/// Errors thrown by `WorkflowModeValidator.validate(_:availableKinds:registeredDescriptors:)`
/// (per #078 L15, extended for #090).
public enum WorkflowModeValidationError: Error, Equatable, Sendable {
    /// Recipe has zero processors. A pipeline with no work to do is
    /// not valid.
    case emptyProcessors

    /// Recipe declares a streaming transcriber processor but its
    /// `pipelineShape` is `.batch`, or vice-versa.
    case streamingShapeMismatch(processorKind: ModelKind, declaredShape: PipelineShape)

    /// Recipe references a `ModelKind` that is not currently available
    /// in `ActiveModelService` (no active descriptor for that kind, or
    /// the kind is gated off). Only fires for *unpinned* specs;
    /// pinned specs (`descriptorID != nil`) bypass this rule.
    case kindUnavailable(ModelKind)

    /// `.diarizedTurns(transcriberKind:)` was given a non-ASR kind.
    case diarizedTurnsRequiresAsrTranscriberKind(provided: ModelKind)

    /// Recipe's `pipelineShape == .streaming` but the processors list
    /// does not contain exactly one streaming-transcriber processor.
    case streamingShapeRequiresExactlyOneStreamingProcessor(count: Int)

    /// Streaming recipes persist an explicit `streamingBehavior`.
    case streamingShapeRequiresStreamingBehavior

    /// Batch recipes must not persist streaming-only behavior.
    case batchShapeForbidsStreamingBehavior

    /// #090: a pinned `descriptorID` references a descriptor that is
    /// not in the supplied `registeredDescriptors` list. Either the
    /// catalog entry was removed or the recipe has a typo. Surfaces
    /// in the modes-editor list as an "unavailable model" badge.
    case pinnedDescriptorNotRegistered(id: String)

    /// #090: a pinned `descriptorID` references a descriptor whose
    /// `kind` differs from the spec's `kind`. E.g. pinning a
    /// diarization descriptor to a `.transcriber(kind: .asr)` spec.
    case pinnedDescriptorKindMismatch(id: String, expected: ModelKind, actual: ModelKind)
}
