import Foundation
import PersonalScribeCore

/// Builds a `BoundRecipe` from a `WorkflowMode` at session start.
///
/// Per L25 (eager descriptor binding):
/// - `ActiveModelService.activeDescriptor(for: kind)` resolves once
///   when this builder runs. The resulting `BoundRecipe` is immutable.
/// - Mid-session `ActiveModelService.setActive(...)` does NOT mutate an
///   in-flight `BoundRecipe`; it takes effect on the next session start.
///
/// Per L19 (parameter cascade): each `Parameter<T>` is resolved eagerly
/// via `ParameterResolver.resolve(_:from:)` against the supplied
/// `UserDefaults`. The bound values are concrete (not closures).
///
/// Throws `RecipeBuildError.kindHasNoActiveDescriptor(_)` when a
/// processor spec references a `ModelKind` that has no active
/// descriptor in `ActiveModelService`. Callers (`SessionCoordinator`
/// per #078.28) surface a descriptive error and abort the session.
@MainActor
public final class RecipeBuilder {
    private let modelService: ActiveModelService
    private let processorProvider: any ModelBoundProcessorProviding
    private let defaults: UserDefaults

    public init(
        modelService: ActiveModelService,
        processorProvider: any ModelBoundProcessorProviding,
        defaults: UserDefaults = .standard
    ) {
        self.modelService = modelService
        self.processorProvider = processorProvider
        self.defaults = defaults
    }

    public func build(_ mode: WorkflowMode) throws -> BoundRecipe {
        let processors = try mode.processors.map { try buildProcessor($0) }
        let captureControllers = mode.captureControllers.map { buildCaptureController($0) }
        let outputSinks = mode.outputSinks.map { buildOutputSink($0) }
        let streamingBehavior = buildStreamingBehavior(mode.streamingBehavior)
        // #098 (2026-05-24): streaming mode's auto-paste setting now
        // flows through unchanged. Pre-#098 behavior filtered out
        // `.frontmostPaste` whenever `liveCursorEnabled == true` to
        // avoid double-pasting at session end. Dogfood proved this was
        // wrong: live cursor only pastes EoU chunks (often zero per
        // session with Parakeet), and the second-pass authoritative
        // final is different text than what was live-pasted. Users
        // want BOTH pasted and choose which they keep. The newline
        // separator between live-pasted chunks and the final paste is
        // owned by `ClipboardBatchOutput` using #097's accumulator
        // signal.
        let streamingSecondPassTranscriber = try buildStreamingSecondPassTranscriber(
            streamingBehavior: streamingBehavior
        )
        return BoundRecipe(
            recipeID: mode.id,
            recipeName: mode.name,
            pipelineShape: mode.pipelineShape,
            processors: processors,
            captureControllers: captureControllers,
            outputSinks: outputSinks,
            streamingBehavior: streamingBehavior,
            streamingSecondPassTranscriber: streamingSecondPassTranscriber
        )
    }

    // MARK: - Per-spec build

    private func buildProcessor(_ spec: ProcessorSpec) throws -> BoundProcessor {
        switch spec {
        case .transcriber(let kind, let descriptorID):
            let descriptor = try resolveDescriptor(for: kind, pinnedID: descriptorID)
            let transcriber = try processorProvider.transcriber(for: descriptor)
            return .transcriber(transcriber)

        case .streamingTranscriber(let kind, let descriptorID):
            let descriptor = try resolveDescriptor(for: kind, pinnedID: descriptorID)
            let transcriber = try processorProvider.streamingTranscriber(for: descriptor)
            return .streamingTranscriber(transcriber)

        case .diarizedTurns(let diarizerKind, let transcriberKind, let transcriberDescriptorID, let sensitivity):
            // Diarizer leg has no pin in #090 (single descriptor in
            // catalog); transcriber leg honors `transcriberDescriptorID`.
            let diarizerDescriptor = try resolveDescriptor(for: diarizerKind, pinnedID: nil)
            let transcriberDescriptor = try resolveDescriptor(
                for: transcriberKind,
                pinnedID: transcriberDescriptorID
            )
            let diarizer = try processorProvider.diarizer(for: diarizerDescriptor)
            let transcriber = try processorProvider.transcriber(for: transcriberDescriptor)
            let resolvedSensitivity = ParameterResolver.resolve(sensitivity, from: defaults)
            return .diarizedTurns(
                diarizer: diarizer,
                transcriber: transcriber,
                sensitivity: resolvedSensitivity
            )
        }
    }

    private func buildCaptureController(_ spec: CaptureControllerSpec) -> BoundCaptureController {
        switch spec {
        case .vad(let enabled, let silenceThreshold, let showWarning, let showAutoStoppedNotification):
            return .vad(
                enabled: ParameterResolver.resolve(enabled, from: defaults),
                silenceThreshold: ParameterResolver.resolve(silenceThreshold, from: defaults),
                showWarning: ParameterResolver.resolve(showWarning, from: defaults),
                showAutoStoppedNotification: ParameterResolver.resolve(
                    showAutoStoppedNotification,
                    from: defaults
                )
            )
        case .manualHotkey:
            return .manualHotkey
        }
    }

    private func buildOutputSink(_ spec: OutputSinkSpec) -> BoundOutputSink {
        switch spec {
        case .clipboard(let restoreEnabled):
            return .clipboard(
                restoreEnabled: ParameterResolver.resolve(restoreEnabled, from: defaults)
            )
        case .frontmostPaste(let enabled):
            return .frontmostPaste(
                enabled: ParameterResolver.resolve(enabled, from: defaults)
            )
        case .transcriptHistorySQLite:
            return .transcriptHistorySQLite
        }
    }

    private func buildStreamingBehavior(
        _ spec: StreamingBehaviorSpec?
    ) -> BoundStreamingBehavior? {
        guard let spec else {
            return nil
        }

        return BoundStreamingBehavior(
            liveCardEnabled: ParameterResolver.resolve(spec.liveCardEnabled, from: defaults),
            liveCursorEnabled: ParameterResolver.resolve(spec.liveCursorEnabled, from: defaults),
            secondPassEnabled: ParameterResolver.resolve(spec.secondPassEnabled, from: defaults)
        )
    }

    private func buildStreamingSecondPassTranscriber(
        streamingBehavior: BoundStreamingBehavior?
    ) throws -> (any Transcriber)? {
        guard let streamingBehavior,
              streamingBehavior.secondPassEnabled,
              let descriptor = modelService.activeDescriptor(for: .asr)
        else {
            return nil
        }
        return try processorProvider.transcriber(for: descriptor)
    }

    /// Resolve the descriptor for a processor spec.
    ///
    /// - When `pinnedID` is non-nil (#090): look up the descriptor in
    ///   `modelService.registeredModels` and verify its `kind` matches.
    ///   The pin wins regardless of the global active selection.
    /// - When `pinnedID` is nil: fall back to
    ///   `modelService.activeDescriptor(for:)` (pre-#090 behavior).
    ///
    /// Pinned-resolution failures are unusual at this layer because
    /// `WorkflowModeValidator` runs upstream at save + session-start.
    /// Defensive errors here protect against test fixtures or future
    /// callers that bypass validation.
    private func resolveDescriptor(
        for kind: ModelKind,
        pinnedID: String?
    ) throws -> ModelDescriptor {
        if let pinnedID {
            guard let pinned = modelService.registeredModels.first(where: { $0.id == pinnedID }) else {
                throw RecipeBuildError.pinnedDescriptorNotRegistered(id: pinnedID)
            }
            guard pinned.kind == kind else {
                throw RecipeBuildError.pinnedDescriptorKindMismatch(
                    id: pinnedID,
                    expected: kind,
                    actual: pinned.kind
                )
            }
            return pinned
        }
        guard let descriptor = modelService.activeDescriptor(for: kind) else {
            throw RecipeBuildError.kindHasNoActiveDescriptor(kind)
        }
        return descriptor
    }
}

public enum RecipeBuildError: Error, Equatable {
    case kindHasNoActiveDescriptor(ModelKind)
    /// #090: a pinned `descriptorID` references a descriptor that is
    /// not in `modelService.registeredModels`. Should be caught by the
    /// validator first; defensive error if reached at build time.
    case pinnedDescriptorNotRegistered(id: String)
    /// #090: a pinned `descriptorID` references a descriptor whose
    /// `kind` differs from the spec's `kind`. Should be caught by the
    /// validator first; defensive error if reached at build time.
    case pinnedDescriptorKindMismatch(id: String, expected: ModelKind, actual: ModelKind)
}
