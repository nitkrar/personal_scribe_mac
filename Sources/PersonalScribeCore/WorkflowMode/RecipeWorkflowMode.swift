import Foundation

/// Recipe-driven mode introduced in #078 (per L1 + L14).
///
/// Composes three role-specific lists:
/// - `processors` — `ProcessorSpec` declarations (ASR / streaming ASR /
///   diarized turns).
/// - `captureControllers` — `CaptureControllerSpec` declarations (VAD,
///   manual hotkey).
/// - `outputSinks` — `OutputSinkSpec` declarations (clipboard, paste,
///   transcript history).
///
/// Plus a `pipelineShape: PipelineShape` (`.batch | .streaming`) that
/// the validator (#078.13) cross-checks against the processor list (a
/// streaming transcriber processor requires `.streaming`).
///
/// Naming: `RecipeWorkflowMode` is **temporary**. Today's legacy
/// `WorkflowMode` (`Sources/PersonalScribeCore/WorkflowMode.swift` —
/// `{id, name, voiceModelID, aiModelID, systemPrompt}`) lives
/// alongside this type through Phase G to keep trunk buildable. At
/// Phase G cutover (#078.30b) the legacy type is renamed to
/// `LegacyWorkflowMode` and `RecipeWorkflowMode` is renamed to
/// `WorkflowMode`.
///
/// Codable: serialised as part of `WorkflowModeDocument` (#078.12) on
/// `workflow-modes.json` in `AppConfig.baseDirectory()`.
///
/// `Identifiable` so Modes-tab UI bindings work directly off `id`.
public struct RecipeWorkflowMode: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let pipelineShape: PipelineShape
    public let processors: [ProcessorSpec]
    public let captureControllers: [CaptureControllerSpec]
    public let outputSinks: [OutputSinkSpec]

    public init(
        id: String,
        name: String,
        pipelineShape: PipelineShape,
        processors: [ProcessorSpec],
        captureControllers: [CaptureControllerSpec],
        outputSinks: [OutputSinkSpec]
    ) {
        self.id = id
        self.name = name
        self.pipelineShape = pipelineShape
        self.processors = processors
        self.captureControllers = captureControllers
        self.outputSinks = outputSinks
    }

    // MARK: - Built-ins

    /// Default Dictation recipe — batch ASR, manual-hotkey capture,
    /// clipboard + paste + history sinks. Mirrors the user-visible
    /// behavior of today's `ModeRegistry.dictation` legacy
    /// `WorkflowMode`. The `.clipboard` restore-enabled parameter
    /// defers to the global `ClipboardRestoreEnabled` preference; the
    /// VAD capture controller is **not** included here — VAD enters
    /// the recipe only when the user has the "Auto-stop after silence"
    /// toggle on (Phase F migration, #078.26).
    public static let dictation = RecipeWorkflowMode(
        id: "dictation",
        name: "Dictation",
        pipelineShape: .batch,
        processors: [.transcriber(kind: .asr)],
        captureControllers: [.manualHotkey],
        outputSinks: [
            .clipboard(
                restoreEnabled: .setting(PreferenceKeys.clipboardRestoreEnabled)
            ),
            .frontmostPaste,
            .transcriptHistorySQLite
        ]
    )
}
