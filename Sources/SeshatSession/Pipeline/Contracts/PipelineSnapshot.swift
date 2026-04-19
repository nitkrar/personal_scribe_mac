import SeshatCore

public struct PipelineSnapshot: Sendable, Equatable {
    public var sessionState: SessionState
    public var activeStage: PipelineStageID?
    public var transcriptProgress: TranscriptProgress?
    public var lastCompletedResult: TranscriptionResult?
    public var recordingDuration: Duration?
    public var context: PipelineContextSnapshot

    public init(
        sessionState: SessionState = .idle,
        activeStage: PipelineStageID? = nil,
        transcriptProgress: TranscriptProgress? = nil,
        lastCompletedResult: TranscriptionResult? = nil,
        recordingDuration: Duration? = nil,
        context: PipelineContextSnapshot
    ) {
        self.sessionState = sessionState
        self.activeStage = activeStage
        self.transcriptProgress = transcriptProgress
        self.lastCompletedResult = lastCompletedResult
        self.recordingDuration = recordingDuration
        self.context = context
    }
}
