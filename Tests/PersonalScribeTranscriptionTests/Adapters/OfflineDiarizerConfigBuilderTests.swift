import FluidAudio
import XCTest
@testable import PersonalScribeCore
@testable import PersonalScribeTranscription

final class OfflineDiarizerConfigBuilderTests: XCTestCase {
    // FluidAudio's `OfflineDiarizerConfig.validate()` rejects clustering
    // thresholds outside `(0, sqrt(2)]` and a few other ranges. This
    // test catches a future preset value that drifts out-of-range or
    // violates a cross-knob constraint we haven't anticipated. Pure
    // value-pinning would be a copy of the spec; this asserts a
    // structural property the FluidAudio side enforces at runtime.
    func testEachPresetProducesAValidConfig() throws {
        for sensitivity in SpeakerSeparationSensitivity.allCases {
            let config = OfflineDiarizerConfigBuilder.makeConfig(for: sensitivity)
            XCTAssertNoThrow(
                try config.validate(),
                "Preset \(sensitivity) produced an OfflineDiarizerConfig that fails FluidAudio's validate()."
            )
        }
    }

    // The two knobs we tune (clusteringThreshold + minSegmentDurationSeconds)
    // must actually move from FluidAudio's defaults — otherwise the
    // preset is a no-op against the live diarizer. Asserts the deltas
    // exist for every non-balanced preset.
    func testNonBalancedPresetsDifferFromFluidAudioDefaults() {
        let defaultConfig = OfflineDiarizerConfig()
        for sensitivity in SpeakerSeparationSensitivity.allCases where sensitivity != .balanced {
            let config = OfflineDiarizerConfigBuilder.makeConfig(for: sensitivity)
            let differs = config.clustering.threshold != defaultConfig.clustering.threshold
                || config.embedding.minSegmentDurationSeconds
                    != defaultConfig.embedding.minSegmentDurationSeconds
            XCTAssertTrue(
                differs,
                "Preset \(sensitivity) must move at least one knob away from FluidAudio defaults."
            )
        }
    }
}
