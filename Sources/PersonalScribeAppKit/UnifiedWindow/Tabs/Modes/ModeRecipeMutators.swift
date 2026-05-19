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
        copy.streamingBehavior = on ? (copy.streamingBehavior ?? .defaultSettings) : nil
        copy.processors = copy.processors.map { spec -> ProcessorSpec in
            switch spec {
            case .transcriber(let kind, _):
                // .asr ↔ .streamingASR are different kinds — a pin on
                // the .asr leg is incompatible with .streamingASR, so
                // toggling realtime CLEARS the pin in either direction.
                return on ? .streamingTranscriber(kind: .streamingASR) : .transcriber(kind: kind)
            case .streamingTranscriber(let kind, _):
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

    func withLanguage(_ language: String?) -> WorkflowMode {
        var copy = self
        copy.language = language.map { Parameter<String?>.override($0) }
        return copy
    }

    func withLiveTranscriptCard(parameter: Parameter<Bool>) -> WorkflowMode {
        rewritingStreamingBehavior { behavior in
            behavior.liveCardEnabled = parameter
        }
    }

    func withLiveCursorStreaming(parameter: Parameter<Bool>) -> WorkflowMode {
        rewritingStreamingBehavior { behavior in
            behavior.liveCursorEnabled = parameter
        }
    }

    func withAuthoritativeSecondPass(parameter: Parameter<Bool>) -> WorkflowMode {
        rewritingStreamingBehavior { behavior in
            behavior.secondPassEnabled = parameter
        }
    }

    func withStreamingEouSilenceThresholdMs(parameter: Parameter<Int>) -> WorkflowMode {
        rewritingStreamingBehavior { behavior in
            behavior.eouSilenceThresholdMs = parameter
        }
    }

    func withDiarization(_ on: Bool) -> WorkflowMode {
        var copy = self
        copy.processors = copy.processors.map { spec -> ProcessorSpec in
            switch spec {
            case .transcriber(let kind, let descriptorID) where on:
                // Same ASR kind on both sides — CARRY the pin from
                // `.transcriber.descriptorID` into the new
                // `.diarizedTurns.transcriberDescriptorID`. Sensitivity
                // defaults to the global preference reference; the
                // user can override it from the mode detail later.
                return .diarizedTurns(
                    diarizerKind: .diarization,
                    transcriberKind: kind,
                    transcriberDescriptorID: descriptorID
                )
            case .diarizedTurns(_, let transcriberKind, let transcriberDescriptorID, _) where !on:
                // Same direction in reverse — CARRY the pin out.
                // Sensitivity is dropped because the destination spec
                // (`.transcriber`) doesn't carry diarization tuning.
                return .transcriber(kind: transcriberKind, descriptorID: transcriberDescriptorID)
            default:
                return spec
            }
        }
        return copy
    }

    /// #090 — Set or clear the per-mode voice-model pin. Operates on
    /// the first transcriber-bearing processor (`.transcriber`,
    /// `.streamingTranscriber`, or `.diarizedTurns`'s ASR leg). Modes
    /// with multiple transcriber-bearing specs aren't producible by
    /// the editor today, so "first match" is sufficient.
    func withVoiceModelPin(_ id: String?) -> WorkflowMode {
        var copy = self
        var didReplace = false
        copy.processors = copy.processors.map { spec -> ProcessorSpec in
            guard !didReplace else { return spec }
            switch spec {
            case .transcriber(let kind, _):
                didReplace = true
                return .transcriber(kind: kind, descriptorID: id)
            case .streamingTranscriber(let kind, _):
                didReplace = true
                return .streamingTranscriber(kind: kind, descriptorID: id)
            case .diarizedTurns(let diarizerKind, let transcriberKind, _, let sensitivity):
                didReplace = true
                return .diarizedTurns(
                    diarizerKind: diarizerKind,
                    transcriberKind: transcriberKind,
                    transcriberDescriptorID: id,
                    sensitivity: sensitivity
                )
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

    /// Per-mode override for the offline diarizer's sensitivity preset.
    /// Operates on the first `.diarizedTurns` processor in the recipe;
    /// modes without a diarized processor are returned unchanged. The
    /// view-model only surfaces the picker when a diarized processor
    /// exists, so the no-op branch is a safety net rather than a
    /// supported path.
    func withSpeakerSeparationSensitivity(
        parameter: Parameter<SpeakerSeparationSensitivity>
    ) -> WorkflowMode {
        var copy = self
        var didReplace = false
        copy.processors = copy.processors.map { spec -> ProcessorSpec in
            guard !didReplace else { return spec }
            switch spec {
            case .diarizedTurns(let diarizerKind, let transcriberKind, let descriptorID, _):
                didReplace = true
                return .diarizedTurns(
                    diarizerKind: diarizerKind,
                    transcriberKind: transcriberKind,
                    transcriberDescriptorID: descriptorID,
                    sensitivity: parameter
                )
            default:
                return spec
            }
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

    func sanitizingLanguage(
        registeredDescriptors: [ModelDescriptor]
    ) -> WorkflowMode {
        var copy = self
        guard let language = copy.language?.resolved, !language.isEmpty else {
            copy.language = nil
            return copy
        }

        guard
            let descriptorID = copy.pinnedDescriptorIDForLanguage(),
            let descriptor = registeredDescriptors.first(where: { $0.id == descriptorID }),
            let supportedLanguages = descriptor.supportedLanguages,
            supportedLanguages.contains(language)
        else {
            copy.language = nil
            return copy
        }

        return copy
    }

    private func rewritingStreamingBehavior(
        _ mutate: (inout StreamingBehaviorSpec) -> Void
    ) -> WorkflowMode {
        var copy = self
        var behavior = copy.streamingBehavior ?? .defaultSettings
        mutate(&behavior)
        copy.streamingBehavior = behavior
        return copy
    }

    private func pinnedDescriptorIDForLanguage() -> String? {
        for spec in processors {
            switch spec {
            case .transcriber(_, let descriptorID):
                if let descriptorID {
                    return descriptorID
                }
            case .streamingTranscriber(_, let descriptorID):
                if let descriptorID {
                    return descriptorID
                }
            case .diarizedTurns(_, _, let descriptorID, _):
                if let descriptorID {
                    return descriptorID
                }
            }
        }

        return nil
    }
}
