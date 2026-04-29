public struct DefaultPostProcessingPipeline: PostProcessingPipeline {
    private let stages: [any PostProcessingStage]

    public init() {
        stages = [FillerRemovalStage(), BasicPunctuationStage()]
    }

    public init(stages: [any PostProcessingStage]) {
        self.stages = stages
    }

    /// Splits the input on `\n` (after normalizing CRLF/CR), runs every
    /// stage on each line, then rejoins with `\n`. Centralizing the
    /// line-awareness here means individual stages can stay
    /// single-text-in / single-text-out without each having to guard
    /// against `\s+`-style regexes eating the inter-turn separators
    /// that diarized recipes (`#078`) emit.
    public func run(_ text: String, context: PostProcessingContext) async throws -> String {
        guard text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            return ""
        }
        let lines = Self.normalizeLineEndings(text)
            .split(separator: "\n", omittingEmptySubsequences: false)
        var processedLines: [String] = []
        processedLines.reserveCapacity(lines.count)
        for line in lines {
            var current = String(line)
            for stage in stages {
                current = try await stage.apply(current, context: context)
            }
            processedLines.append(current)
        }
        return processedLines.joined(separator: "\n")
    }

    private static func normalizeLineEndings(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }
}
