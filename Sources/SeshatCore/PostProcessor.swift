import Foundation

/// Pure, deterministic text cleanup. Two stages:
/// 1. Filler-word removal: strips um, uh, er, you know, like, i mean, etc.
/// 2. Basic punctuation: trims whitespace, ensures trailing sentence terminator, capitalizes first letter.
///
/// Does NOT use an LLM. Safe to run in SessionCoordinator before surfacing lastResult.
public struct PostProcessor: Sendable {
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

    public init() {}

    public func clean(_ raw: String) -> String {
        let stageOne = removeFillers(from: raw)
        return applyBasicPunctuation(to: stageOne)
    }

    private func removeFillers(from raw: String) -> String {
        let withoutSingleWordFillers = Self.singleWordFillers.stringByReplacingMatches(
            in: raw,
            range: NSRange(raw.startIndex..., in: raw),
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

    private func applyBasicPunctuation(to text: String) -> String {
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
