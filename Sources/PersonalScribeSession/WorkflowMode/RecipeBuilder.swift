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
        return BoundRecipe(
            recipeID: mode.id,
            recipeName: mode.name,
            pipelineShape: mode.pipelineShape,
            processors: processors,
            captureControllers: captureControllers,
            outputSinks: outputSinks
        )
    }

    // MARK: - Per-spec build

    private func buildProcessor(_ spec: ProcessorSpec) throws -> BoundProcessor {
        switch spec {
        case .transcriber(let kind):
            let descriptor = try resolveDescriptor(for: kind)
            let transcriber = try processorProvider.transcriber(for: descriptor)
            return .transcriber(transcriber)

        case .streamingTranscriber(let kind):
            let descriptor = try resolveDescriptor(for: kind)
            let transcriber = try processorProvider.streamingTranscriber(for: descriptor)
            return .streamingTranscriber(transcriber)

        case .diarizedTurns(let diarizerKind, let transcriberKind):
            let diarizerDescriptor = try resolveDescriptor(for: diarizerKind)
            let transcriberDescriptor = try resolveDescriptor(for: transcriberKind)
            let diarizer = try processorProvider.diarizer(for: diarizerDescriptor)
            let transcriber = try processorProvider.transcriber(for: transcriberDescriptor)
            return .diarizedTurns(diarizer: diarizer, transcriber: transcriber)
        }
    }

    private func buildCaptureController(_ spec: CaptureControllerSpec) -> BoundCaptureController {
        switch spec {
        case .vad(let silenceThreshold, let showWarning, let showAutoStoppedNotification):
            return .vad(
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
        case .frontmostPaste:
            return .frontmostPaste
        case .transcriptHistorySQLite:
            return .transcriptHistorySQLite
        }
    }

    private func resolveDescriptor(for kind: ModelKind) throws -> ModelDescriptor {
        guard let descriptor = modelService.activeDescriptor(for: kind) else {
            throw RecipeBuildError.kindHasNoActiveDescriptor(kind)
        }
        return descriptor
    }
}

public enum RecipeBuildError: Error, Equatable {
    case kindHasNoActiveDescriptor(ModelKind)
}
