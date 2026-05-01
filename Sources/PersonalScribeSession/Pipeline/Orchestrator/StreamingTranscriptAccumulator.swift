import Foundation
import PersonalScribeCore

struct StreamingTranscriptAccumulator: Sendable {
    private(set) var committedUtterances: [String] = []
    private(set) var inProgressUtterance: String?
    private(set) var terminalFinalResult: TranscriptionResult?

    mutating func apply(_ event: StreamingTranscriptionEvent) -> String? {
        switch event {
        case .partial(let text):
            let normalized = Self.normalize(text)
            inProgressUtterance = normalized.isEmpty ? nil : normalized
            return cumulativeText

        case .endOfUtterance(let text):
            let normalized = Self.normalize(text)
            if !normalized.isEmpty {
                committedUtterances.append(normalized)
            }
            inProgressUtterance = nil
            return cumulativeText

        case .finalized(let result):
            terminalFinalResult = result
            return nil
        }
    }

    var cumulativeText: String {
        var parts = committedUtterances
        if let inProgressUtterance, !inProgressUtterance.isEmpty {
            parts.append(inProgressUtterance)
        }
        return parts.joined(separator: " ")
    }

    var terminalText: String {
        if let terminalFinalResult {
            let normalized = Self.normalize(terminalFinalResult.text)
            if !normalized.isEmpty {
                return normalized
            }
        }
        return cumulativeText
    }

    var hasTranscriptContent: Bool {
        !terminalText.isEmpty
    }

    private static func normalize(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
