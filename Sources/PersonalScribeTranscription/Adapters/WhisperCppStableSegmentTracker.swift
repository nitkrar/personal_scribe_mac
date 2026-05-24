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
        var normalized = ""
        var needsSeparator = false

        for scalar in text.lowercased().unicodeScalars {
            switch scalar {
            case "'", "’":
                continue
            case _ where CharacterSet.alphanumerics.contains(scalar):
                if needsSeparator, !normalized.isEmpty {
                    normalized.append(" ")
                }
                normalized.unicodeScalars.append(scalar)
                needsSeparator = false
            default:
                needsSeparator = true
            }
        }

        return normalized
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

    private func dropCommittedPrefixOverlap(from incoming: [TrackedSegment]) -> [TrackedSegment] {
        guard !incoming.isEmpty, !committedSegments.isEmpty else {
            return incoming
        }

        let committed = committedSegments.map(Self.normalizeSegment)
        var bestOverlap = SegmentOverlap()

        for committedStartIndex in committed.indices {
            let committedSuffix = Array(committed[committedStartIndex...])
            guard
                let committedStartMs = committedSuffix.first?.segment.startMs,
                let committedEndMs = committedSuffix.last?.segment.endMs
            else {
                continue
            }

            let committedText = Self.joinNormalizedText(committedSuffix.map(\.normalizedText))
            var incomingPieces: [String] = []
            var previousIncomingText = ""

            for incomingIndex in incoming.indices {
                incomingPieces.append(incoming[incomingIndex].normalizedText)
                let incomingText = Self.joinNormalizedText(incomingPieces)

                if committedText.hasPrefix(incomingText) {
                    if incomingText == committedText,
                       rangesMatch(
                           startMs: committedStartMs,
                           endMs: committedEndMs,
                           otherStartMs: incoming[0].segment.startMs,
                           otherEndMs: incoming[incomingIndex].segment.endMs
                       )
                    {
                        bestOverlap.updateIfBetter(
                            overlapLength: committedText.count,
                            dropCount: incomingIndex + 1
                        )
                    }

                    previousIncomingText = incomingText
                    continue
                }

                guard incomingText.hasPrefix(committedText) else {
                    break
                }

                guard
                    rangesMatch(
                        startMs: committedStartMs,
                        endMs: committedEndMs,
                        otherStartMs: incoming[0].segment.startMs,
                        otherEndMs: incoming[incomingIndex].segment.endMs
                    ),
                    let prefixWithinCurrentSegment = Self.normalizedCommittedPrefixWithinCurrentSegment(
                        committedText: committedText,
                        previousIncomingText: previousIncomingText,
                        currentSegmentText: incoming[incomingIndex].normalizedText
                    )
                else {
                    break
                }

                bestOverlap.updateIfBetter(
                    overlapLength: committedText.count,
                    dropCount: incomingIndex,
                    stripPrefixFromNextSegment: prefixWithinCurrentSegment
                )
                break
            }
        }

        guard bestOverlap.overlapLength > 0 else {
            return incoming
        }

        var remaining = Array(incoming.dropFirst(bestOverlap.dropCount))
        guard
            let stripPrefix = bestOverlap.stripPrefixFromNextSegment,
            !remaining.isEmpty
        else {
            return remaining
        }

        if let strippedSegment = Self.strippingNormalizedPrefix(
            stripPrefix,
            from: remaining[0]
        ) {
            remaining[0] = strippedSegment
        } else {
            remaining.removeFirst()
        }
        return remaining
    }

    private static func normalizedCommittedPrefixWithinCurrentSegment(
        committedText: String,
        previousIncomingText: String,
        currentSegmentText: String
    ) -> String? {
        let prefix: String
        if previousIncomingText.isEmpty {
            prefix = committedText
        } else {
            let previousWithSeparator = previousIncomingText + " "
            guard committedText.hasPrefix(previousWithSeparator) else {
                return nil
            }
            prefix = String(committedText.dropFirst(previousWithSeparator.count))
        }

        guard !prefix.isEmpty, currentSegmentText.hasPrefix(prefix) else {
            return nil
        }
        return prefix
    }

    private static func strippingNormalizedPrefix(
        _ normalizedPrefix: String,
        from segment: TrackedSegment
    ) -> TrackedSegment? {
        guard let cutIndex = cutIndex(
            afterConsumingNormalizedPrefix: normalizedPrefix,
            in: segment.segment.text
        ) else {
            return nil
        }

        let strippedText = segment.segment.text[cutIndex...]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedTail = normalizeText(String(strippedText))
        guard !normalizedTail.isEmpty else {
            return nil
        }

        return TrackedSegment(
            segment: WhisperCppDecodedSegment(
                text: String(strippedText),
                startMs: segment.segment.startMs,
                endMs: segment.segment.endMs
            ),
            normalizedText: normalizedTail,
            confirmations: segment.confirmations
        )
    }

    private static func cutIndex(
        afterConsumingNormalizedPrefix normalizedPrefix: String,
        in original: String
    ) -> String.Index? {
        guard !normalizedPrefix.isEmpty else {
            return original.startIndex
        }

        var emitted = ""
        var cutIndices: [String.Index] = []
        var needsSeparator = false
        var scalarIndex = original.unicodeScalars.startIndex

        while scalarIndex < original.unicodeScalars.endIndex {
            let scalar = original.unicodeScalars[scalarIndex]
            let nextScalarIndex = original.unicodeScalars.index(after: scalarIndex)

            for loweredScalar in String(scalar).lowercased().unicodeScalars {
                switch loweredScalar {
                case "'", "’":
                    continue
                case _ where CharacterSet.alphanumerics.contains(loweredScalar):
                    if needsSeparator, !emitted.isEmpty {
                        emitted.append(" ")
                        cutIndices.append(nextScalarIndex)
                    }
                    emitted.append(contentsOf: String(loweredScalar))
                    cutIndices.append(nextScalarIndex)
                    needsSeparator = false
                default:
                    needsSeparator = true
                }

                guard normalizedPrefix.hasPrefix(emitted) else {
                    return nil
                }

                if emitted == normalizedPrefix {
                    return cutIndices.last
                }
            }

            scalarIndex = nextScalarIndex
        }

        return emitted == normalizedPrefix ? cutIndices.last : nil
    }

    private struct SegmentOverlap {
        var overlapLength = 0
        var dropCount = 0
        var stripPrefixFromNextSegment: String?

        mutating func updateIfBetter(
            overlapLength: Int,
            dropCount: Int,
            stripPrefixFromNextSegment: String? = nil
        ) {
            guard overlapLength > self.overlapLength else {
                return
            }
            self.overlapLength = overlapLength
            self.dropCount = dropCount
            self.stripPrefixFromNextSegment = stripPrefixFromNextSegment
        }
    }

    private func merge(existing: [TrackedSegment], incoming: [TrackedSegment]) -> [TrackedSegment] {
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

        return rangesMatch(
            startMs: lhs.segment.startMs,
            endMs: lhs.segment.endMs,
            otherStartMs: rhs.segment.startMs,
            otherEndMs: rhs.segment.endMs
        )
    }

    private static func joinNormalizedText<S: Sequence>(_ pieces: S) -> String
    where S.Element == String {
        pieces
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private func rangesMatch(
        startMs: Int64,
        endMs: Int64,
        otherStartMs: Int64,
        otherEndMs: Int64
    ) -> Bool {
        let startDrift = abs(startMs - otherStartMs)
        let endDrift = abs(endMs - otherEndMs)
        let overlapsWithDrift =
            startMs <= otherEndMs + maxTimeDriftMs
            && otherStartMs <= endMs + maxTimeDriftMs
        return overlapsWithDrift || (startDrift <= maxTimeDriftMs && endDrift <= maxTimeDriftMs)
    }
}
