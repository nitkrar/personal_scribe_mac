import Foundation

public struct LegacyWorkflowMode: Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let voiceModelID: String
    public let aiModelID: String?
    public let systemPrompt: String?

    public init(
        id: String,
        name: String,
        voiceModelID: String,
        aiModelID: String? = nil,
        systemPrompt: String? = nil
    ) {
        self.id = id
        self.name = name
        self.voiceModelID = voiceModelID
        self.aiModelID = aiModelID
        self.systemPrompt = systemPrompt
    }
}

public enum ModeRegistry {
    public static let dictation = LegacyWorkflowMode(
        id: "dictation",
        name: "Dictation",
        voiceModelID: BuiltInModelCatalog.defaultModelId
    )

    public static let all: [LegacyWorkflowMode] = [dictation]

    public static func descriptor(for id: String) -> LegacyWorkflowMode? {
        all.first { $0.id == id }
    }

    public static let defaultModeID: String = dictation.id
}
