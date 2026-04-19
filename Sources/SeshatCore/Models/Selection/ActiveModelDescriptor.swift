import Foundation

public struct ActiveModelDescriptor: Codable, Sendable, Equatable {
    public let voiceModel: ModelDescriptor
    public let aiModelID: String?

    public init(
        voiceModel: ModelDescriptor,
        aiModelID: String? = nil
    ) {
        self.voiceModel = voiceModel
        self.aiModelID = aiModelID
    }
}
