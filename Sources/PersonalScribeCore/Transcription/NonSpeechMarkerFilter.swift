import Foundation

/// Removes non-speech annotations that Whisper-family models emit for
/// silence or background noise — `[BLANK_AUDIO]`, `[ Silence ]`,
/// `(upbeat music)` — so they never reach the live card, the cursor, or
/// the pasted transcript. Square-bracket spans are always annotations
/// (dictation doesn't produce them); parenthesized spans are removed
/// only when they describe a sound, so dictated parentheses survive.
public enum NonSpeechMarkerFilter {
    private static let soundWords = [
        "music", "noise", "silence", "silent", "blank", "applause", "laugh",
        "laughs", "laughing", "laughter", "inaudible", "static", "cough",
        "coughs", "coughing", "sigh", "sighs", "breath", "breathing", "wind",
        "beep", "click", "clicking", "typing",
    ]

    private static let bracketPattern = try! NSRegularExpression(pattern: #"\[[^\]]*\]"#)
    private static let soundParenPattern = try! NSRegularExpression(
        pattern: #"\((?=[^)]*\b(?:"# + soundWords.joined(separator: "|") + #")\b)[^)]*\)"#,
        options: [.caseInsensitive]
    )
    private static let spaceRunPattern = try! NSRegularExpression(pattern: #"[ \t]{2,}"#)

    public static func strip(_ text: String) -> String {
        var result = text
        for pattern in [bracketPattern, soundParenPattern] {
            result = pattern.stringByReplacingMatches(
                in: result,
                range: NSRange(result.startIndex..., in: result),
                withTemplate: ""
            )
        }
        result = spaceRunPattern.stringByReplacingMatches(
            in: result,
            range: NSRange(result.startIndex..., in: result),
            withTemplate: " "
        )
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

extension TranscriptionResult {
    /// Same result with non-speech markers stripped from the text and
    /// segments; segments left empty are dropped. Metadata is preserved.
    public func removingNonSpeechMarkers() -> TranscriptionResult {
        TranscriptionResult(
            text: NonSpeechMarkerFilter.strip(text),
            segments: segments.compactMap { segment in
                let cleaned = NonSpeechMarkerFilter.strip(segment.text)
                return cleaned.isEmpty
                    ? nil
                    : Segment(text: cleaned, start: segment.start, end: segment.end)
            },
            audioDuration: audioDuration,
            processingDuration: processingDuration,
            confidence: confidence,
            tokenTimings: tokenTimings,
            performanceMetrics: performanceMetrics,
            ctcDetectedTerms: ctcDetectedTerms,
            ctcAppliedTerms: ctcAppliedTerms
        )
    }
}

extension StreamingTranscriptionEvent {
    public func removingNonSpeechMarkers() -> StreamingTranscriptionEvent {
        switch self {
        case .partial(let text):
            return .partial(text: NonSpeechMarkerFilter.strip(text))
        case .endOfUtterance(let text):
            return .endOfUtterance(text: NonSpeechMarkerFilter.strip(text))
        case .finalized(let result):
            return .finalized(result.removingNonSpeechMarkers())
        }
    }
}
