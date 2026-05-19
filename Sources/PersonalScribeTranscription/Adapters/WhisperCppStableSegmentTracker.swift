import Foundation

struct WhisperCppDecodedSegment: Sendable, Equatable {
    let text: String
    let startMs: Int64
    let endMs: Int64
}

struct WhisperCppStableSegmentTracker: Sendable {
    private struct TrackedSegment: Sendable, Equatable {
        let segment: WhisperCppDecodedSegment
        let normalizedText: String
        let confirmations: Int
    }

    private let confirmationThreshold: Int
    private let maxTimeDriftMs: Int64
    private var committedChunks: [String] = []
    private var committedSegments: [WhisperCppDecodedSegment] = []
    private var activeSegments: [TrackedSegment] = []

    init(
        confirmationThreshold: Int = 2,
        maxTimeDriftMs: Int64 = 400
    ) {
        self.confirmationThreshold = confirmationThreshold
        self.maxTimeDriftMs = maxTimeDriftMs
    }

    @discardableResult
    mutating func ingest(_ decodedSegments: [WhisperCppDecodedSegment]) -> String {
        let normalizedIncoming = dropCommittedPrefixOverlap(
            from: decodedSegments
                .map(Self.normalizeSegment)
                .filter { !$0.normalizedText.isEmpty }
        )
        activeSegments = merge(existing: activeSegments, incoming: normalizedIncoming)
        return partialText
    }

    mutating func flushStablePrefix() -> String? {
        let stableSegments = Array(activeSegments.prefix(stablePrefixCount).map(\.segment))
        let text = Self.joinText(stableSegments.map(\.text))
        guard !text.isEmpty else {
            return nil
        }

        committedChunks.append(text)
        committedSegments.append(contentsOf: stableSegments)
        activeSegments.removeFirst(stableSegments.count)
        return text
    }

    var currentUtteranceText: String {
        Self.joinText(activeSegments.map(\.segment.text))
    }

    var pendingStableText: String {
        Self.joinText(activeSegments.prefix(stablePrefixCount).map(\.segment.text))
    }

    var partialText: String {
        Self.joinText(activeSegments.dropFirst(stablePrefixCount).map(\.segment.text))
    }

    var finalText: String {
        let current = currentUtteranceText
        var parts = committedChunks
        if !current.isEmpty {
            parts.append(current)
        }
        return Self.joinText(parts)
    }
}

private extension WhisperCppStableSegmentTracker {
    private var stablePrefixCount: Int {
        activeSegments.prefix { $0.confirmations >= confirmationThreshold }.count
    }

    private static func joinText<S: Sequence>(_ pieces: S) -> String where S.Element == String {
        pieces
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static func normalizeText(_ text: String) -> String {
        text
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .lowercased()
    }

    private static func normalizeSegment(_ segment: WhisperCppDecodedSegment) -> TrackedSegment {
        let trimmed = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
        return TrackedSegment(
            segment: WhisperCppDecodedSegment(
                text: trimmed,
                startMs: segment.startMs,
                endMs: segment.endMs
            ),
            normalizedText: normalizeText(trimmed),
            confirmations: 1
        )
    }

    private func dropCommittedPrefixOverlap(
        from incoming: [TrackedSegment]
    ) -> [TrackedSegment] {
        guard !incoming.isEmpty, !committedSegments.isEmpty else {
            return incoming
        }

        let committed = committedSegments.map(Self.normalizeSegment)
        let maxOverlap = min(committed.count, incoming.count)
        for overlapCount in stride(from: maxOverlap, through: 1, by: -1) {
            let committedSuffix = committed.suffix(overlapCount)
            let incomingPrefix = incoming.prefix(overlapCount)
            if zip(committedSuffix, incomingPrefix).allSatisfy(segmentsMatch) {
                return Array(incoming.dropFirst(overlapCount))
            }
        }

        return incoming
    }

    private func merge(
        existing: [TrackedSegment],
        incoming: [TrackedSegment]
    ) -> [TrackedSegment] {
        guard !existing.isEmpty else {
            return incoming
        }
        guard !incoming.isEmpty else {
            return existing
        }

        var merged: [TrackedSegment] = []
        var existingIndex = 0

        for incomingSegment in incoming {
            var matched = false

            while existingIndex < existing.count {
                let candidate = existing[existingIndex]
                if segmentsMatch(candidate, incomingSegment) {
                    merged.append(
                        TrackedSegment(
                            segment: incomingSegment.segment,
                            normalizedText: incomingSegment.normalizedText,
                            confirmations: candidate.confirmations + 1
                        )
                    )
                    existingIndex += 1
                    matched = true
                    break
                }

                if candidate.confirmations >= confirmationThreshold,
                   existingIndex == merged.count {
                    merged.append(candidate)
                    existingIndex += 1
                    continue
                }

                existingIndex += 1
            }

            if !matched {
                merged.append(incomingSegment)
            }
        }

        while existingIndex < existing.count,
              existing[existingIndex].confirmations >= confirmationThreshold,
              existingIndex == merged.count
        {
            merged.append(existing[existingIndex])
            existingIndex += 1
        }

        return merged
    }

    private func segmentsMatch(_ lhs: TrackedSegment, _ rhs: TrackedSegment) -> Bool {
        guard lhs.normalizedText == rhs.normalizedText else {
            return false
        }

        let startDrift = abs(lhs.segment.startMs - rhs.segment.startMs)
        let endDrift = abs(lhs.segment.endMs - rhs.segment.endMs)
        let overlapsWithDrift =
            lhs.segment.startMs <= rhs.segment.endMs + maxTimeDriftMs
            && rhs.segment.startMs <= lhs.segment.endMs + maxTimeDriftMs
        return overlapsWithDrift || (startDrift <= maxTimeDriftMs && endDrift <= maxTimeDriftMs)
    }
}
