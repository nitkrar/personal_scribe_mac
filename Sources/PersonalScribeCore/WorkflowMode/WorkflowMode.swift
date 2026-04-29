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
/// Phase G cutover (#078.30b) renamed the legacy `WorkflowMode`
/// (`{id, name, voiceModelID, aiModelID, systemPrompt}`) to
/// `LegacyWorkflowMode` and promoted this recipe-driven type to the
/// canonical `WorkflowMode` name.
///
/// `glyph` (#089) — SF Symbol name displayed as the row's leading icon.
/// Fixed-by-preset; no user-pickable glyph in V1. Defaults to `"mic"`
/// on missing-key decode for forward-compat with documents written
/// pre-#089.
///
/// `hotkey` (#089) — optional per-mode hotkey. `nil` = mode invoked via
/// menu-bar / pill switcher only; non-nil = a dedicated binding that
/// activates this mode AND starts recording.
///
/// Codable: serialised as part of `WorkflowModeDocument` (#078.12) on
/// `workflow-modes.json` in `AppConfig.baseDirectory()`.
///
/// `Identifiable` so Modes-tab UI bindings work directly off `id`.
public struct WorkflowMode: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public var name: String
    public var glyph: String
    public var hotkey: HotkeyPreference?
    public var pipelineShape: PipelineShape
    public var processors: [ProcessorSpec]
    public var captureControllers: [CaptureControllerSpec]
    public var outputSinks: [OutputSinkSpec]

    public init(
        id: String,
        name: String,
        glyph: String = "mic",
        hotkey: HotkeyPreference? = nil,
        pipelineShape: PipelineShape,
        processors: [ProcessorSpec],
        captureControllers: [CaptureControllerSpec],
        outputSinks: [OutputSinkSpec]
    ) {
        self.id = id
        self.name = name
        self.glyph = glyph
        self.hotkey = hotkey
        self.pipelineShape = pipelineShape
        self.processors = processors
        self.captureControllers = captureControllers
        self.outputSinks = outputSinks
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case glyph
        case hotkey
        case pipelineShape
        case processors
        case captureControllers
        case outputSinks
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.name = try container.decode(String.self, forKey: .name)
        self.glyph = try container.decodeIfPresent(String.self, forKey: .glyph) ?? "mic"
        self.hotkey = try container.decodeIfPresent(HotkeyPreference.self, forKey: .hotkey)
        self.pipelineShape = try container.decode(PipelineShape.self, forKey: .pipelineShape)
        self.processors = try container.decode([ProcessorSpec].self, forKey: .processors)
        self.captureControllers = try container.decode(
            [CaptureControllerSpec].self,
            forKey: .captureControllers
        )
        self.outputSinks = try container.decode([OutputSinkSpec].self, forKey: .outputSinks)
    }

    // MARK: - Built-ins

    /// Built-in fallback Dictation recipe (#089 L-1). Used when
    /// `customModes` is empty or `defaultModeID` is unset / stale.
    /// **Never rendered in the Modes UI.** Every overridable parameter
    /// resolves through `Parameter.setting(...)` so the GeneralTab
    /// global toggles drive fallback behavior unchanged (L-26).
    public static let dictation = WorkflowMode(
        id: "dictation",
        name: "Dictation",
        glyph: "mic",
        hotkey: nil,
        pipelineShape: .batch,
        processors: [.transcriber(kind: .asr)],
        captureControllers: [
            .manualHotkey,
            .vad(
                enabled: .setting(PreferenceKeys.vadAutoStopEnabled),
                silenceThreshold: .setting(PreferenceKeys.vadSilenceThreshold),
                showWarning: .setting(PreferenceKeys.vadShowStoppingWarning),
                showAutoStoppedNotification: .setting(
                    PreferenceKeys.vadShowAutoStoppedNotification
                )
            )
        ],
        outputSinks: [
            .clipboard(
                restoreEnabled: .setting(PreferenceKeys.clipboardRestoreEnabled)
            ),
            .frontmostPaste(
                enabled: .setting(PreferenceKeys.autoPasteEnabled)
            ),
            .transcriptHistorySQLite
        ]
    )
}
