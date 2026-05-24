@preconcurrency import WhisperKit
import Foundation
import PersonalScribeCore

struct WhisperKitStreamingState: Sendable, Equatable {
    let confirmedSegments: [TranscriptionSegment]
    let unconfirmedSegments: [TranscriptionSegment]
}

struct WhisperKitStreamingLedger: Sendable {
    private struct TimedText: Sendable {
        let start: Float
        let end: Float
        let text: String
    }

    private var lastCommittedSegmentEndSeconds: Float = 0
    private var committedUtterances: [String] = []
    private var currentPartialText = ""
    private var lastEmittedPartialText = ""

    mutating func consume(_ state: WhisperKitStreamingState) -> [StreamingTranscriptionEvent] {
        var events: [StreamingTranscriptionEvent] = []
        let newlyConfirmed = state.confirmedSegments.filter {
            $0.end > lastCommittedSegmentEndSeconds
        }
        if let lastConfirmedEnd = newlyConfirmed.last?.end {
            lastCommittedSegmentEndSeconds = max(lastCommittedSegmentEndSeconds, lastConfirmedEnd)
        }

        let stableText = Self.joinedText(newlyConfirmed)
        let emittedStable = !stableText.isEmpty
        if emittedStable {
            committedUtterances.append(stableText)
            events.append(.endOfUtterance(text: stableText))
        }

        let partialText = Self.joinedText(state.unconfirmedSegments)
        currentPartialText = partialText
        if partialText.isEmpty {
            lastEmittedPartialText = ""
        } else if !emittedStable, partialText != lastEmittedPartialText {
            lastEmittedPartialText = partialText
            events.append(.partial(text: partialText))
        }

        return events
    }

    func finalText(fallbackState: WhisperKitStreamingState?) -> String {
        if let fallbackState {
            let stateText = Self.joinedText(
                fallbackState.confirmedSegments + fallbackState.unconfirmedSegments
            )
            if !stateText.isEmpty {
                return stateText
            }
        }

        if currentPartialText.isEmpty {
            return Self.joinedText(committedUtterances)
        }
        return Self.joinedText(committedUtterances + [currentPartialText])
    }

    static func joinedText(_ segments: [TranscriptionSegment]) -> String {
        let cleanedSegments = segments.compactMap { segment -> TimedText? in
            let text = sanitizePiece(segment.text)
            guard !text.isEmpty else {
                return nil
            }
            return TimedText(
                start: segment.start,
                end: segment.end,
                text: text
            )
        }

        guard !cleanedSegments.isEmpty else {
            return ""
        }

        var mergedSegments: [TimedText] = []
        for segment in cleanedSegments {
            while let last = mergedSegments.last, segment.start <= last.start {
                mergedSegments.removeLast()
            }

            if let last = mergedSegments.last, segment.start < last.end {
                mergedSegments[mergedSegments.count - 1] = TimedText(
                    start: last.start,
                    end: max(last.end, segment.end),
                    text: mergeOverlappingText(base: last.text, next: segment.text)
                )
            } else {
                mergedSegments.append(segment)
            }
        }

        return joinedText(mergedSegments.map(\.text))
    }

    private static func joinedText(_ pieces: [String]) -> String {
        pieces
            .map(sanitizePiece)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func sanitizePiece(_ text: String) -> String {
        text
            .replacingOccurrences(
                of: "<\\|[^|]*\\|>",
                with: "",
                options: .regularExpression
            )
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    private static func mergeOverlappingText(base: String, next: String) -> String {
        guard !base.isEmpty else {
            return next
        }
        guard !next.isEmpty else {
            return base
        }
        if next == base || next.hasPrefix(base) {
            return next
        }
        if base.hasPrefix(next) {
            return base
        }

        let baseWords = base.split(whereSeparator: \.isWhitespace).map(String.init)
        let nextWords = next.split(whereSeparator: \.isWhitespace).map(String.init)
        let maxOverlap = min(baseWords.count, nextWords.count)

        for overlap in stride(from: maxOverlap, through: 1, by: -1) {
            if Array(baseWords.suffix(overlap)) == Array(nextWords.prefix(overlap)) {
                return (baseWords + nextWords.dropFirst(overlap)).joined(separator: " ")
            }
        }

        return "\(base) \(next)"
    }
}
