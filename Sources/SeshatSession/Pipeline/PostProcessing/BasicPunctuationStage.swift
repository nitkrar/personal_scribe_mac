import Foundation

public struct BasicPunctuationStage: PostProcessingStage {
    public let name = "basic-punctuation"

    public init() {}

    public func apply(_ text: String, context: PostProcessingContext) async throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return ""
        }

        let punctuated: String
        if let lastCharacter = trimmed.last, ".!?".contains(lastCharacter) {
            punctuated = trimmed
        } else {
            punctuated = trimmed + "."
        }

        return punctuated.prefix(1).uppercased() + punctuated.dropFirst()
    }
}
