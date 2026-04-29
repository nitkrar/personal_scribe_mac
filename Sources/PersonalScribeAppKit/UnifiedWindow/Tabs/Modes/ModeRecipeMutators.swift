import Foundation
import PersonalScribeCore

/// Pure recipe mutators consumed by `ModeDetailViewModel` (#089).
/// Each function takes a `WorkflowMode` and returns a new instance
/// with the relevant slice rebuilt — no shared state, no UserDefaults
/// reads. Rebuilds are conservative: only the affected list is
/// rewritten; everything else carries through.
extension WorkflowMode {

    func withRealtime(_ on: Bool) -> WorkflowMode {
        var copy = self
        copy.pipelineShape = on ? .streaming : .batch
        copy.processors = copy.processors.map { spec -> ProcessorSpec in
            switch spec {
            case .transcriber(let kind):
                return on ? .streamingTranscriber(kind: .streamingASR) : .transcriber(kind: kind)
            case .streamingTranscriber(let kind):
                return on ? .streamingTranscriber(kind: kind) : .transcriber(kind: .asr)
            case .diarizedTurns:
                // Diarization can't run in streaming mode V1 — drop the
                // toggle silently when realtime is requested. Validator
                // will catch genuinely-broken combos at save.
                return spec
            }
        }
        return copy
    }

    func withDiarization(_ on: Bool) -> WorkflowMode {
        var copy = self
        copy.processors = copy.processors.map { spec -> ProcessorSpec in
            switch spec {
            case .transcriber(let kind) where on:
                return .diarizedTurns(diarizerKind: .diarization, transcriberKind: kind)
            case .diarizedTurns(_, let transcriberKind) where !on:
                return .transcriber(kind: transcriberKind)
            default:
                return spec
            }
        }
        return copy
    }

    func withAutoStop(parameter: Parameter<Bool>) -> WorkflowMode {
        var copy = self
        var didReplace = false
        copy.captureControllers = copy.captureControllers.map { spec -> CaptureControllerSpec in
            if case .vad(_, let threshold, let warn, let notify) = spec {
                didReplace = true
                return .vad(
                    enabled: parameter,
                    silenceThreshold: threshold,
                    showWarning: warn,
                    showAutoStoppedNotification: notify
                )
            }
            return spec
        }
        if !didReplace {
            // Recipe didn't have a `.vad` controller yet — append one
            // with sensible defaults from globals so the toggle has a
            // place to bind.
            copy.captureControllers.append(
                .vad(
                    enabled: parameter,
                    silenceThreshold: .setting(PreferenceKeys.vadSilenceThreshold),
                    showWarning: .setting(PreferenceKeys.vadShowStoppingWarning),
                    showAutoStoppedNotification: .setting(
                        PreferenceKeys.vadShowAutoStoppedNotification
                    )
                )
            )
        }
        return copy
    }

    func withAutoPaste(parameter: Parameter<Bool>) -> WorkflowMode {
        var copy = self
        var didReplace = false
        copy.outputSinks = copy.outputSinks.map { spec -> OutputSinkSpec in
            if case .frontmostPaste = spec {
                didReplace = true
                return .frontmostPaste(enabled: parameter)
            }
            return spec
        }
        if !didReplace {
            copy.outputSinks.append(.frontmostPaste(enabled: parameter))
        }
        return copy
    }

    func withRestoreClipboard(parameter: Parameter<Bool>) -> WorkflowMode {
        var copy = self
        var didReplace = false
        copy.outputSinks = copy.outputSinks.map { spec -> OutputSinkSpec in
            if case .clipboard = spec {
                didReplace = true
                return .clipboard(restoreEnabled: parameter)
            }
            return spec
        }
        if !didReplace {
            copy.outputSinks.insert(
                .clipboard(restoreEnabled: parameter),
                at: 0
            )
        }
        return copy
    }

    func withHotkey(_ hotkey: HotkeyPreference?) -> WorkflowMode {
        var copy = self
        copy.hotkey = hotkey
        return copy
    }

    func withName(_ name: String) -> WorkflowMode {
        var copy = self
        copy.name = name
        return copy
    }
}
