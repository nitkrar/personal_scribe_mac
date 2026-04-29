import Foundation

/// Pure-function central validator for `WorkflowMode` (per #078
/// L15, extended for #090). Fires at three sites: recipe save
/// (registry), modes-list validity recompute, and session start
/// (`SessionCoordinator`).
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
/// 5. Every *unpinned* `ModelKind` referenced by a processor must be
///    present in the supplied `availableKinds` set; otherwise
///    `.kindUnavailable(...)` is thrown. Pinned specs
///    (`descriptorID != nil`) bypass this rule — pinning is exactly
///    the mechanism by which a recipe declares its own model
///    independent of the global active descriptor.
/// 6. Every pinned `descriptorID` must reference a descriptor in the
///    supplied `registeredDescriptors` list, AND that descriptor's
///    `kind` must match the spec's kind.
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
    ///   - registeredDescriptors: descriptors known to the model
    ///     registry. Used to validate per-mode pins (#090). Defaults
    ///     to `[]` so existing callers/tests that don't exercise
    ///     pinned recipes don't have to thread a list through.
    public static func validate(
        _ mode: WorkflowMode,
        availableKinds: Set<ModelKind>,
        registeredDescriptors: [ModelDescriptor] = []
    ) throws {
        // Rule 1: non-empty processors.
        guard !mode.processors.isEmpty else {
            throw WorkflowModeValidationError.emptyProcessors
        }

        // Per-processor checks.
        var streamingProcessorCount = 0
        for processor in mode.processors {
            switch processor {
            case .transcriber(let kind, let descriptorID):
                if mode.pipelineShape != .batch {
                    throw WorkflowModeValidationError.streamingShapeMismatch(
                        processorKind: kind,
                        declaredShape: mode.pipelineShape
                    )
                }
                try requireKindAvailableOrPinned(
                    kind,
                    descriptorID: descriptorID,
                    availableKinds: availableKinds,
                    registeredDescriptors: registeredDescriptors
                )

            case .streamingTranscriber(let kind, let descriptorID):
                if mode.pipelineShape != .streaming {
                    throw WorkflowModeValidationError.streamingShapeMismatch(
                        processorKind: kind,
                        declaredShape: mode.pipelineShape
                    )
                }
                try requireKindAvailableOrPinned(
                    kind,
                    descriptorID: descriptorID,
                    availableKinds: availableKinds,
                    registeredDescriptors: registeredDescriptors
                )
                streamingProcessorCount += 1

            case .diarizedTurns(
                let diarizerKind,
                let transcriberKind,
                let transcriberDescriptorID,
                _
            ):
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
                // Diarizer leg: no pin slot in #090 (only one diarizer
                // descriptor in the catalog today). Always validates
                // through availableKinds.
                try requireKindAvailableOrPinned(
                    diarizerKind,
                    descriptorID: nil,
                    availableKinds: availableKinds,
                    registeredDescriptors: registeredDescriptors
                )
                // Transcriber leg: honor the pin if present.
                try requireKindAvailableOrPinned(
                    transcriberKind,
                    descriptorID: transcriberDescriptorID,
                    availableKinds: availableKinds,
                    registeredDescriptors: registeredDescriptors
                )
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

    /// Combined Rule-5 + Rule-6 check. When `descriptorID` is non-nil
    /// (pinned), the spec bypasses `availableKinds` and instead
    /// validates that the pinned descriptor is registered + its kind
    /// matches. When `descriptorID` is nil (unpinned), Rule 5 applies
    /// unchanged.
    private static func requireKindAvailableOrPinned(
        _ kind: ModelKind,
        descriptorID: String?,
        availableKinds: Set<ModelKind>,
        registeredDescriptors: [ModelDescriptor]
    ) throws {
        if let descriptorID {
            guard let descriptor = registeredDescriptors.first(where: { $0.id == descriptorID }) else {
                throw WorkflowModeValidationError.pinnedDescriptorNotRegistered(id: descriptorID)
            }
            guard descriptor.kind == kind else {
                throw WorkflowModeValidationError.pinnedDescriptorKindMismatch(
                    id: descriptorID,
                    expected: kind,
                    actual: descriptor.kind
                )
            }
            return
        }
        guard availableKinds.contains(kind) else {
            throw WorkflowModeValidationError.kindUnavailable(kind)
        }
    }
}
