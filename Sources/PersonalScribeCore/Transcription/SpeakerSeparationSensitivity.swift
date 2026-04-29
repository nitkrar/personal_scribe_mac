import Foundation

/// User-facing tuning preset for speaker diarization. Higher sensitivity
/// (`.relaxed`) lowers the clustering threshold and shortens the minimum
/// embedding window — both push the diarizer toward splitting similar
/// voices into separate speakers. Lower sensitivity (`.strict`) tightens
/// both, preferring sticky speaker labels at the cost of merging similar
/// voices.
///
/// `.balanced` is the FluidAudio community-1 baseline.
///
/// Values are codified per case to keep the mapping a single source of
/// truth; the FluidAudio adapter consumes `.parameters` to build an
/// `OfflineDiarizerConfig` at session start.
public enum SpeakerSeparationSensitivity: String, CaseIterable, Sendable, Codable {
    case relaxed
    case balanced
    case strict

    public var parameters: SpeakerSeparationParameters {
        switch self {
        case .relaxed:
            SpeakerSeparationParameters(
                clusteringThreshold: 0.55,
                minSegmentDurationSeconds: 0.6
            )
        case .balanced:
            SpeakerSeparationParameters(
                clusteringThreshold: 0.60,
                minSegmentDurationSeconds: 1.0
            )
        case .strict:
            SpeakerSeparationParameters(
                clusteringThreshold: 0.68,
                minSegmentDurationSeconds: 1.4
            )
        }
    }
}

/// Vendor-neutral tuning values exposed by `SpeakerSeparationSensitivity`.
/// The FluidAudio adapter (`PersonalScribeTranscription`) translates these
/// to `OfflineDiarizerConfig` fields; defining the value type in `Core`
/// keeps the domain enum free of FluidAudio dependencies.
public struct SpeakerSeparationParameters: Sendable, Equatable {
    /// Euclidean distance threshold for unit-normalized speaker embeddings.
    /// Lower values produce more clusters (more speakers detected); higher
    /// values fold similar voices together.
    public let clusteringThreshold: Double

    /// Minimum speech duration (seconds) for a turn to qualify for
    /// embedding extraction. Lower values let shorter utterances
    /// participate in clustering; higher values restrict embeddings to
    /// longer, more reliable segments.
    public let minSegmentDurationSeconds: Double

    public init(
        clusteringThreshold: Double,
        minSegmentDurationSeconds: Double
    ) {
        self.clusteringThreshold = clusteringThreshold
        self.minSegmentDurationSeconds = minSegmentDurationSeconds
    }
}
