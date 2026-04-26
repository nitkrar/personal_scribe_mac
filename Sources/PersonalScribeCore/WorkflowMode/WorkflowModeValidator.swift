import Foundation

/// Pure-function central validator for `RecipeWorkflowMode` (per #078
/// L15). Fires at three sites: recipe save (registry), recipe build
/// (`RecipeBuilder`), and session start (`SessionCoordinator`).
///
/// Rules:
/// 1. At least one processor.
/// 2. `.streamingTranscriber(...)` processor requires
///    `pipelineShape == .streaming`. Conversely, `.transcriber(...)`
///    or `.diarizedTurns(...)` processor requires
///    `pipelineShape == .batch`.
/// 3. `pipelineShape == .streaming` requires exactly one
///    streaming-transcriber processor.
/// 4. `.diarizedTurns(transcriberKind:)` requires `transcriberKind` to
///    be `.asr` or `.streamingASR`.
/// 5. Every `ModelKind` referenced by a processor must be present in
///    the supplied `availableKinds` set; otherwise
///    `.kindUnavailable(...)` is thrown. Callers pass the currently-
///    active set from `ActiveModelService` (production) or a fixed
///    set (tests).
///
/// Caseless enum: namespace only. The validator is stateless — every
/// call evaluates the same rules against its inputs.
public enum WorkflowModeValidator {
    /// Validate a recipe. Throws on the first rule violation.
    ///
    /// - Parameters:
    ///   - mode: the recipe to validate.
    ///   - availableKinds: kinds for which `ActiveModelService` has
    ///     an active descriptor. Passed in by the caller so this
    ///     function stays pure / testable.
    public static func validate(
        _ mode: RecipeWorkflowMode,
        availableKinds: Set<ModelKind>
    ) throws {
        // Rule 1: non-empty processors.
        guard !mode.processors.isEmpty else {
            throw WorkflowModeValidationError.emptyProcessors
        }

        // Per-processor checks.
        var streamingProcessorCount = 0
        for processor in mode.processors {
            switch processor {
            case .transcriber(let kind):
                if mode.pipelineShape != .batch {
                    throw WorkflowModeValidationError.streamingShapeMismatch(
                        processorKind: kind,
                        declaredShape: mode.pipelineShape
                    )
                }
                try requireKindAvailable(kind, in: availableKinds)

            case .streamingTranscriber(let kind):
                if mode.pipelineShape != .streaming {
                    throw WorkflowModeValidationError.streamingShapeMismatch(
                        processorKind: kind,
                        declaredShape: mode.pipelineShape
                    )
                }
                try requireKindAvailable(kind, in: availableKinds)
                streamingProcessorCount += 1

            case .diarizedTurns(let diarizerKind, let transcriberKind):
                if mode.pipelineShape != .batch {
                    throw WorkflowModeValidationError.streamingShapeMismatch(
                        processorKind: diarizerKind,
                        declaredShape: mode.pipelineShape
                    )
                }
                guard transcriberKind == .asr || transcriberKind == .streamingASR else {
                    throw WorkflowModeValidationError
                        .diarizedTurnsRequiresAsrTranscriberKind(
                            provided: transcriberKind
                        )
                }
                try requireKindAvailable(diarizerKind, in: availableKinds)
                try requireKindAvailable(transcriberKind, in: availableKinds)
            }
        }

        // Rule 3: streaming shape must have exactly one streaming
        // processor.
        if mode.pipelineShape == .streaming, streamingProcessorCount != 1 {
            throw WorkflowModeValidationError
                .streamingShapeRequiresExactlyOneStreamingProcessor(
                    count: streamingProcessorCount
                )
        }
    }

    private static func requireKindAvailable(
        _ kind: ModelKind,
        in available: Set<ModelKind>
    ) throws {
        guard available.contains(kind) else {
            throw WorkflowModeValidationError.kindUnavailable(kind)
        }
    }
}
