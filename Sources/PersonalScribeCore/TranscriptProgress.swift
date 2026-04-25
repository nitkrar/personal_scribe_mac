public struct TranscriptProgress: Sendable, Equatable {
    public let revision: Int
    public let text: String
    public let isFinal: Bool
    public let sourceStage: PipelineStepID

    public init(
        revision: Int,
        text: String,
        isFinal: Bool,
        sourceStage: PipelineStepID
    ) {
        self.revision = revision
        self.text = text
        self.isFinal = isFinal
        self.sourceStage = sourceStage
    }
}
