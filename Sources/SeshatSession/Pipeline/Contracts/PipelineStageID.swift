public enum PipelineStageID: String, CaseIterable, Sendable, Equatable {
    case capture
    case transcription
    case postProcessing
    case persistence
    case output
}
