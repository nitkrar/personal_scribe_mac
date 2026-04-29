import FluidAudio
import PersonalScribeCore

/// Translates the vendor-neutral `SpeakerSeparationSensitivity` preset
/// into a FluidAudio `OfflineDiarizerConfig`. Only the two knobs
/// codified in `SpeakerSeparationParameters` move; the rest stay at
/// FluidAudio's `community-1` defaults across all three presets.
///
/// Onset/offset/stepRatio/Fa/Fb tuning is deliberately deferred — the
/// safest v1 keeps unpredictability scoped to clustering threshold +
/// minimum embedding window. Add more knobs once dogfooding shows the
/// existing ones aren't enough.
enum OfflineDiarizerConfigBuilder {
    static func makeConfig(
        for sensitivity: SpeakerSeparationSensitivity
    ) -> OfflineDiarizerConfig {
        let parameters = sensitivity.parameters
        var config = OfflineDiarizerConfig()
        config.clustering.threshold = parameters.clusteringThreshold
        config.embedding.minSegmentDurationSeconds = parameters.minSegmentDurationSeconds
        return config
    }
}
