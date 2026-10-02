import Foundation

public struct FillerRemovalStage: PostProcessingStage {
    /// Vocal fillers only. "like", "I mean", "kind of" etc. are real words as often as
    /// not, and a regex can't tell which, so they stay.
    private static let fillers = try! NSRegularExpression(
        pattern: #"\b(um|uh|uhm|er|erm|ah|ahh|hmm|hmmm)\b"#,
        options: [.caseInsensitive]
    )
    private static let repeatedWhitespace = try! NSRegularExpression(
        pattern: #"\s+"#
    )
    private static let leadingPunctuationWhitespace = try! NSRegularExpression(
        pattern: #"\s+([,.!?;:])"#
    )
    private static let trailingPunctuationWhitespace = try! NSRegularExpression(
        pattern: #"([,.!?;:])\s+"#
    )

    public let name = "filler-removal"

    public init() {}

    public func apply(_ text: String, context: PostProcessingContext) async throws -> String {
        let withoutFillers = Self.fillers.stringByReplacingMatches(
            in: text,
            range: NSRange(text.startIndex..., in: text),
            withTemplate: " "
        )
        let collapsedWhitespace = Self.repeatedWhitespace.stringByReplacingMatches(
            in: withoutFillers,
            range: NSRange(withoutFillers.startIndex..., in: withoutFillers),
            withTemplate: " "
        )
        let trimmedLeadingPunctuationWhitespace = Self.leadingPunctuationWhitespace.stringByReplacingMatches(
            in: collapsedWhitespace,
            range: NSRange(collapsedWhitespace.startIndex..., in: collapsedWhitespace),
            withTemplate: "$1"
        )

        return Self.trailingPunctuationWhitespace.stringByReplacingMatches(
            in: trimmedLeadingPunctuationWhitespace,
            range: NSRange(trimmedLeadingPunctuationWhitespace.startIndex..., in: trimmedLeadingPunctuationWhitespace),
            withTemplate: "$1 "
        )
    }
}
