import Foundation

/// Engine capabilities are derived from the engine enum; callers use
/// membership checks rather than a fictional single "kind" for
/// engines that satisfy multiple routes.
extension TranscriptionEngine {
    public var capabilities: Set<ModelKind> {
        switch self {
        case .parakeetTDT:
            return [.asr]
        case .qwen3ASR:
            return [.asr]
        case .whisperKit:
            return [.asr, .streamingASR]
        case .whisperCpp:
            return [.asr, .streamingASR]
        case .parakeetEOU:
            return [.streamingASR]
        case .diarization:
            return [.diarization]
        }
    }
}
