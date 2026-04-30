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
/// `preset` (#027) — preset family the mode was minted from. Drives
/// the transcript-row badge (#032) so the row always shows the preset
/// name ("Notes", "Meeting", …) regardless of what the user named the
/// custom mode. Decode falls back to `Preset.inferred(fromGlyph:)` for
/// pre-#027 documents — L-16 fixes glyph per preset, so the inference
/// is exact.
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
    public var preset: Preset
    public var hotkey: HotkeyPreference?
    public var pipelineShape: PipelineShape
    public var processors: [ProcessorSpec]
    public var captureControllers: [CaptureControllerSpec]
    public var outputSinks: [OutputSinkSpec]

    public init(
        id: String,
        name: String,
        glyph: String = "mic",
        preset: Preset = .dictation,
        hotkey: HotkeyPreference? = nil,
        pipelineShape: PipelineShape,
        processors: [ProcessorSpec],
        captureControllers: [CaptureControllerSpec],
        outputSinks: [OutputSinkSpec]
    ) {
        self.id = id
        self.name = name
        self.glyph = glyph
        self.preset = preset
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
        case preset
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
        let glyph = try container.decodeIfPresent(String.self, forKey: .glyph) ?? "mic"
        self.glyph = glyph
        // #027 — pre-#027 documents have no `preset` field. Infer from
        // glyph (L-16: glyph fixed-by-preset, so exact match).
        self.preset = try container.decodeIfPresent(Preset.self, forKey: .preset)
            ?? Preset.inferred(fromGlyph: glyph)
        self.hotkey = try container.decodeIfPresent(HotkeyPreference.self, forKey: .hotkey)
        self.pipelineShape = try container.decode(PipelineShape.self, forKey: .pipelineShape)
        self.processors = try container.decode([ProcessorSpec].self, forKey: .processors)
        self.captureControllers = try container.decode(
            [CaptureControllerSpec].self,
            forKey: .captureControllers
        )
        self.outputSinks = try container.decode([OutputSinkSpec].self, forKey: .outputSinks)
    }

    // MARK: - ID generation (#027)

    /// Mint an id of the form `"{cleanName}-{suffix}"` for a custom
    /// mode. The cleanName strips dashes from `name` (the format's only
    /// reserved separator) so a transcript-row badge can recover a
    /// display fallback for an orphaned mode reference via
    /// `id.split(separator: "-").first`. The suffix is short random
    /// hex so reusing a name (e.g. "Meeting" deleted then re-created)
    /// still produces a fresh, non-colliding id.
    ///
    /// Empty / dash-only names fall back to `"mode"` so the id stays
    /// well-formed.
    public static func makeID(name: String, suffix: String? = nil) -> String {
        let cleaned = cleanName(name)
        let s = suffix ?? randomSuffix()
        return "\(cleaned)-\(s)"
    }

    /// Strip dashes and trim whitespace from a user-typed mode name to
    /// produce the cleanName segment of `makeID`. Falls back to
    /// `"mode"` when the result is empty.
    public static func cleanName(_ name: String) -> String {
        let stripped = name.replacingOccurrences(of: "-", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return stripped.isEmpty ? "mode" : stripped
    }

    /// 6-char lowercase hex suffix sourced from a fresh UUID — enough
    /// entropy for collision-free reuse across a single user's history
    /// of custom modes. Internal storage; users never see the suffix
    /// since the badge fallback path strips it via split-on-`-`.
    public static func randomSuffix() -> String {
        let raw = UUID().uuidString.lowercased().replacingOccurrences(of: "-", with: "")
        return String(raw.prefix(6))
    }

    /// True when `id` matches the legacy `custom-{UUID}` format that
    /// `Preset.materialize` produced before #027. Drives the one-time
    /// migration path in `WorkflowModeRegistry.init`.
    public static func isLegacyID(_ id: String) -> Bool {
        id.hasPrefix("custom-")
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
        preset: .dictation,
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
