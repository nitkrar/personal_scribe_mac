public struct TranscriptProgress: Sendable, Equatable {
    public let revision: Int
    public let text: String
    public let isFinal: Bool
    public let sourceStage: PipelineStageID

    public init(
        revision: Int,
        text: String,
        isFinal: Bool,
        sourceStage: PipelineStageID
    ) {
        self.revision = revision
        self.text = text
        self.isFinal = isFinal
        self.sourceStage = sourceStage
    }
}
