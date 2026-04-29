import Foundation
import PersonalScribeCore
import PersonalScribeSession

/// View-model for the mode-detail screen (#089). Owns the in-flight
/// edit; setters rebuild the recipe via `WorkflowMode` mutators and
/// autosave to the registry.
@MainActor
final class ModeDetailViewModel: ObservableObject {
    @Published private(set) var mode: WorkflowMode
    @Published var lastError: String? = nil

    private let registry: WorkflowModeRegistry

    init(mode: WorkflowMode, registry: WorkflowModeRegistry) {
        self.mode = mode
        self.registry = registry
    }

    var realtimeOn: Bool {
        switch mode.pipelineShape {
        case .streaming: return true
        case .batch: return false
        }
    }

    var diarizationOn: Bool {
        mode.processors.contains { spec in
            if case .diarizedTurns = spec { return true }
            return false
        }
    }

    var autoStopParameter: Parameter<Bool> {
        for controller in mode.captureControllers {
            if case .vad(let enabled, _, _, _) = controller {
                return enabled
            }
        }
        return .setting(PreferenceKeys.vadAutoStopEnabled)
    }

    var autoPasteParameter: Parameter<Bool> {
        for sink in mode.outputSinks {
            if case .frontmostPaste(let enabled) = sink {
                return enabled
            }
        }
        return .setting(PreferenceKeys.autoPasteEnabled)
    }

    var restoreClipboardParameter: Parameter<Bool> {
        for sink in mode.outputSinks {
            if case .clipboard(let restore) = sink {
                return restore
            }
        }
        return .setting(PreferenceKeys.clipboardRestoreEnabled)
    }

    /// #090 — Per-mode voice-model pin. Reads through to the first
    /// transcriber-bearing processor's `descriptorID`. `nil` means
    /// "use globally active", which is the default.
    var voiceModelPinID: String? {
        for spec in mode.processors {
            switch spec {
            case .transcriber(_, let id): return id
            case .streamingTranscriber(_, let id): return id
            case .diarizedTurns(_, _, let id): return id
            }
        }
        return nil
    }

    func setRealtime(_ on: Bool) { apply(mode.withRealtime(on)) }
    func setDiarization(_ on: Bool) { apply(mode.withDiarization(on)) }
    func setAutoStop(_ parameter: Parameter<Bool>) { apply(mode.withAutoStop(parameter: parameter)) }
    func setAutoPaste(_ parameter: Parameter<Bool>) { apply(mode.withAutoPaste(parameter: parameter)) }
    func setRestoreClipboard(_ parameter: Parameter<Bool>) { apply(mode.withRestoreClipboard(parameter: parameter)) }
    func setHotkey(_ hotkey: HotkeyPreference?) { apply(mode.withHotkey(hotkey)) }
    func setVoiceModelPin(_ id: String?) { apply(mode.withVoiceModelPin(id)) }

    func setName(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != mode.name else { return }
        apply(mode.withName(trimmed))
    }

    /// Sibling per-mode hotkeys (excluding self) — passed to the
    /// recorder for collision detection (#089 L-23).
    func siblingHotkeyReservations() -> [HotkeyPreference] {
        registry.customModes
            .filter { $0.id != mode.id }
            .compactMap(\.hotkey)
    }

    private func apply(_ updated: WorkflowMode) {
        do {
            try registry.saveCustom(updated)
            mode = updated
            lastError = nil
        } catch {
            lastError = (error as? LocalizedError)?.errorDescription ?? "\(error)"
        }
    }
}
