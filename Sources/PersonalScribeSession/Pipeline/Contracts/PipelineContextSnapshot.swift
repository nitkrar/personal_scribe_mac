import PersonalScribeCore

public struct PipelineContextSnapshot: Sendable, Equatable {
    public let activeMode: WorkflowMode?
    public let activeAIModelID: String?
    public let systemPrompt: String?
    public let streamingOutputEnabled: Bool

    public init(
        activeMode: WorkflowMode? = nil,
        activeAIModelID: String? = nil,
        systemPrompt: String? = nil,
        streamingOutputEnabled: Bool
    ) {
        self.activeMode = activeMode
        self.activeAIModelID = activeAIModelID
        self.systemPrompt = systemPrompt
        self.streamingOutputEnabled = streamingOutputEnabled
    }
}
