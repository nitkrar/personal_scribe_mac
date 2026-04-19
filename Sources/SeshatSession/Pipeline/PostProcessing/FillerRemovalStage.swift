import Foundation

public struct FillerRemovalStage: PostProcessingStage {
    private static let singleWordFillers = try! NSRegularExpression(
        pattern: #"\b(um|uh|uhm|er|erm|ah|ahh|hmm|hmmm|like)\b"#,
        options: [.caseInsensitive]
    )
    private static let hedges = try! NSRegularExpression(
        pattern: #"\b(you know|i mean|i guess|sort of|kind of)\b"#,
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
        let withoutSingleWordFillers = Self.singleWordFillers.stringByReplacingMatches(
            in: text,
            range: NSRange(text.startIndex..., in: text),
            withTemplate: " "
        )
        let withoutHedges = Self.hedges.stringByReplacingMatches(
            in: withoutSingleWordFillers,
            range: NSRange(withoutSingleWordFillers.startIndex..., in: withoutSingleWordFillers),
            withTemplate: " "
        )
        let collapsedWhitespace = Self.repeatedWhitespace.stringByReplacingMatches(
            in: withoutHedges,
            range: NSRange(withoutHedges.startIndex..., in: withoutHedges),
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
