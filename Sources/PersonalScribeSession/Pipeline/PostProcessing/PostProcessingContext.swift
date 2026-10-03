import PersonalScribeCore

public struct PostProcessingContext: Sendable, Equatable {
    public let recordingDuration: Duration
    public let activeMode: WorkflowMode?
    public let activeAIModelID: String?
    public let systemPrompt: String?
    public let segments: [TranscriptionResult.Segment]
    public let asrConfidence: Double?
    /// `false` delivers the transcript untouched.
    public let cleanupEnabled: Bool

    public init(
        recordingDuration: Duration,
        activeMode: WorkflowMode? = nil,
        activeAIModelID: String? = nil,
        systemPrompt: String? = nil,
        segments: [TranscriptionResult.Segment] = [],
        asrConfidence: Double? = nil,
        cleanupEnabled: Bool = true
    ) {
        self.recordingDuration = recordingDuration
        self.activeMode = activeMode
        self.activeAIModelID = activeAIModelID
        self.systemPrompt = systemPrompt
        self.segments = segments
        self.asrConfidence = asrConfidence
        self.cleanupEnabled = cleanupEnabled
    }
}
