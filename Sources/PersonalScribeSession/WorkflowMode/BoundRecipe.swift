import Foundation
import PersonalScribeCore

/// Runtime-bound view of a `RecipeWorkflowMode` (#078.27).
///
/// Produced by `RecipeBuilder` at session start. Holds **resolved**
/// adapter instances + parameter values, eager per L25: descriptor
/// lookups happen once and the bound recipe is immutable for the
/// lifetime of the session. Mid-session `ActiveModelService.setActive`
/// does NOT mutate an in-flight `BoundRecipe` — the change takes effect
/// only on the next session start.
///
/// The orchestrator (#078.29) consumes this directly instead of
/// branching on legacy `ModeDescriptor` flags.
public struct BoundRecipe: Sendable {
    public let recipeID: String
    public let recipeName: String
    public let pipelineShape: PipelineShape
    public let processors: [BoundProcessor]
    public let captureControllers: [BoundCaptureController]
    public let outputSinks: [BoundOutputSink]

    public init(
        recipeID: String,
        recipeName: String,
        pipelineShape: PipelineShape,
        processors: [BoundProcessor],
        captureControllers: [BoundCaptureController],
        outputSinks: [BoundOutputSink]
    ) {
        self.recipeID = recipeID
        self.recipeName = recipeName
        self.pipelineShape = pipelineShape
        self.processors = processors
        self.captureControllers = captureControllers
        self.outputSinks = outputSinks
    }
}

/// Concrete adapter resolved for a `ProcessorSpec`. Holds typed
/// adapter references suitable for the orchestrator's per-output
/// dispatch.
public enum BoundProcessor: Sendable {
    case transcriber(any Transcriber2)
    case streamingTranscriber(any StreamingTranscriber)
    case diarizedTurns(diarizer: any SpeakerDiarizer, transcriber: any Transcriber2)
}

/// Resolved capture-controller config. VAD parameters resolved eagerly
/// per L25 (no lazy reads inside the orchestrator's hot path).
public enum BoundCaptureController: Sendable, Equatable {
    case vad(
        silenceThreshold: TimeInterval,
        showWarning: Bool,
        showAutoStoppedNotification: Bool
    )
    case manualHotkey
}

/// Resolved output-sink config. Clipboard restore-enabled resolved
/// eagerly.
public enum BoundOutputSink: Sendable, Equatable {
    case clipboard(restoreEnabled: Bool)
    case frontmostPaste
    case transcriptHistorySQLite
}
