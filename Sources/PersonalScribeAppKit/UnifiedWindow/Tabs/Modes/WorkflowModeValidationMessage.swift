import Foundation
import PersonalScribeCore

/// User-facing copy for mode validation failures, shared by the modes
/// list (validity badges) and the mode detail screen (failed edits).
/// `hasDownloadedModel` distinguishes "download one" from "activate one".
enum WorkflowModeValidationMessage {
    static func text(
        for error: Error,
        hasDownloadedModel anyDownloaded: (ModelKind) -> Bool
    ) -> String {
        if let validation = error as? WorkflowModeValidationError {
            switch validation {
            case .emptyProcessors:
                return "Pipeline needs at least one processor."
            case .streamingShapeMismatch(let kind, let shape):
                return "\(kind.rawValue) processor doesn't match \(shape) pipeline."
            case .kindUnavailable(let kind):
                switch kind {
                case .asr:
                    return anyDownloaded(.asr)
                        ? "Voice model not active. Activate one in AI Models."
                        : "Voice model not downloaded. Download one in AI Models."
                case .streamingASR:
                    return anyDownloaded(.streamingASR)
                        ? "Realtime ASR model not active. Activate one in AI Models."
                        : "Realtime requires a streaming ASR model. Download one in AI Models."
                case .diarization:
                    return anyDownloaded(.diarization)
                        ? "Diarization model not active. Activate one in AI Models."
                        : "Diarization model not downloaded. Download one in AI Models."
                case .vad, .tts:
                    return "Required model not available."
                }
            case .diarizedTurnsRequiresAsrTranscriberKind:
                return "Diarization requires an ASR transcriber."
            case .streamingShapeRequiresExactlyOneStreamingProcessor:
                return "Realtime needs a single streaming transcriber."
            case .streamingShapeRequiresStreamingBehavior:
                return "Realtime needs streaming settings."
            case .batchShapeForbidsStreamingBehavior:
                return "Batch modes can't keep realtime-only settings."
            case .pinnedDescriptorNotRegistered(let id):
                return "Pinned model \"\(id)\" is no longer available. Pick another in the mode's settings."
            case .pinnedDescriptorKindMismatch(let id, let expected, _):
                return "Pinned model \"\(id)\" can't be used as \(expected.displayName). Pick another in the mode's settings."
            case .languageRequiresPinnedDescriptor:
                return "Language hint requires a specific pinned voice model. Pick one in the mode's settings."
            case .languageRequiresMultilingualPinnedDescriptor(let id):
                return "Pinned model \"\(id)\" doesn't support language selection. Choose a multilingual model or clear the language."
            }
        }
        return (error as? LocalizedError)?.errorDescription ?? "\(error)"
    }
}
