import PersonalScribeCore

public struct PostProcessingContext: Sendable, Equatable {
    public let recordingDuration: Duration
    public let activeMode: ModeDescriptor?
    public let activeAIModelID: String?
    public let systemPrompt: String?
    public let segments: [TranscriptionResult.Segment]
    public let asrConfidence: Double?

    public init(
        recordingDuration: Duration,
        activeMode: ModeDescriptor? = nil,
        activeAIModelID: String? = nil,
        systemPrompt: String? = nil,
        segments: [TranscriptionResult.Segment] = [],
        asrConfidence: Double? = nil
    ) {
        self.recordingDuration = recordingDuration
        self.activeMode = activeMode
        self.activeAIModelID = activeAIModelID
        self.systemPrompt = systemPrompt
        self.segments = segments
        self.asrConfidence = asrConfidence
    }
}
