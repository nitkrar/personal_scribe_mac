import Foundation
import PersonalScribeCore

/// Code-defined templates the modes editor's `+` popover applies to
/// seed a fresh `WorkflowMode` (#089 L-14). Not a stored type — once
/// the user picks a preset, the `materialize(name:)` factory snapshots
/// the preset's recipe shape into a custom mode that lives in
/// `WorkflowModeDocument.customModes`.
///
/// V1 ships four presets. Glyphs are fixed-by-preset (#089 L-16); no
/// glyph picker.
public enum Preset: String, CaseIterable, Sendable, Identifiable {
    case dictation
    case notes
    case meeting
    case streamingDictation

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .dictation: return "Dictation"
        case .notes: return "Notes"
        case .meeting: return "Meeting"
        case .streamingDictation: return "Streaming Dictation"
        }
    }

    public var glyph: String {
        switch self {
        case .dictation: return "mic"
        case .notes: return "note.text"
        case .meeting: return "person.2.wave.2"
        case .streamingDictation: return "bolt.horizontal"
        }
    }

    public var subtitle: String {
        switch self {
        case .dictation: return "Quick voice-to-cursor with auto-paste."
        case .notes: return "Save transcripts to clipboard without auto-pasting."
        case .meeting: return "Long-form recording with speaker diarization."
        case .streamingDictation: return "See transcript as you speak."
        }
    }

    /// Build the `WorkflowMode` instance from this preset. The caller
    /// (the modes-list view-model) supplies the user-facing `name`
    /// computed via `WorkflowModeRegistry.nextAvailableName(_:)`. The
    /// id is generated fresh from a UUID — it never collides with
    /// existing custom or built-in IDs.
    public func materialize(name: String) -> WorkflowMode {
        let id = "custom-\(UUID().uuidString.lowercased())"
        switch self {
        case .dictation:
            return WorkflowMode(
                id: id,
                name: name,
                glyph: glyph,
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
                    ),
                ],
                outputSinks: [
                    .clipboard(
                        restoreEnabled: .setting(PreferenceKeys.clipboardRestoreEnabled)
                    ),
                    .frontmostPaste(
                        enabled: .setting(PreferenceKeys.autoPasteEnabled)
                    ),
                    .transcriptHistorySQLite,
                ]
            )
        case .notes:
            return WorkflowMode(
                id: id,
                name: name,
                glyph: glyph,
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
                    ),
                ],
                outputSinks: [
                    .clipboard(
                        restoreEnabled: .setting(PreferenceKeys.clipboardRestoreEnabled)
                    ),
                    // Notes preset deliberately overrides auto-paste OFF —
                    // user pastes manually so the transcript lands in the
                    // note app on their schedule.
                    .frontmostPaste(enabled: .override(false)),
                    .transcriptHistorySQLite,
                ]
            )
        case .meeting:
            return WorkflowMode(
                id: id,
                name: name,
                glyph: glyph,
                hotkey: nil,
                pipelineShape: .batch,
                processors: [
                    .diarizedTurns(
                        diarizerKind: .diarization,
                        transcriberKind: .asr,
                        sensitivity: .setting(PreferenceKeys.speakerSeparationSensitivity)
                    ),
                ],
                captureControllers: [
                    .manualHotkey,
                    // Long-form: auto-stop forced off so meetings don't
                    // truncate during silences.
                    .vad(
                        enabled: .override(false),
                        silenceThreshold: .setting(PreferenceKeys.vadSilenceThreshold),
                        showWarning: .setting(PreferenceKeys.vadShowStoppingWarning),
                        showAutoStoppedNotification: .setting(
                            PreferenceKeys.vadShowAutoStoppedNotification
                        )
                    ),
                ],
                outputSinks: [
                    .clipboard(
                        restoreEnabled: .setting(PreferenceKeys.clipboardRestoreEnabled)
                    ),
                    .frontmostPaste(enabled: .override(false)),
                    .transcriptHistorySQLite,
                ]
            )
        case .streamingDictation:
            return WorkflowMode(
                id: id,
                name: name,
                glyph: glyph,
                hotkey: nil,
                pipelineShape: .streaming,
                processors: [.streamingTranscriber(kind: .streamingASR)],
                captureControllers: [
                    .manualHotkey,
                    .vad(
                        enabled: .setting(PreferenceKeys.vadAutoStopEnabled),
                        silenceThreshold: .setting(PreferenceKeys.vadSilenceThreshold),
                        showWarning: .setting(PreferenceKeys.vadShowStoppingWarning),
                        showAutoStoppedNotification: .setting(
                            PreferenceKeys.vadShowAutoStoppedNotification
                        )
                    ),
                ],
                outputSinks: [
                    .clipboard(
                        restoreEnabled: .setting(PreferenceKeys.clipboardRestoreEnabled)
                    ),
                    .frontmostPaste(
                        enabled: .setting(PreferenceKeys.autoPasteEnabled)
                    ),
                    .transcriptHistorySQLite,
                ]
            )
        }
    }
}
