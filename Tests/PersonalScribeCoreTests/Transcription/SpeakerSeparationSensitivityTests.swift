import XCTest
@testable import PersonalScribeCore

final class SpeakerSeparationSensitivityTests: XCTestCase {
    // Catches an accidental value swap between presets — e.g., someone
    // pastes `relaxed`'s value into `strict`'s case. Pure value-pinning
    // would just be the spec twice; this asserts an ordering invariant
    // that's load-bearing for the user-facing semantics: relaxed must
    // produce *more* speaker splits than strict, which is what lower
    // clusteringThreshold + shorter minSegmentDurationSeconds together
    // achieve.
    func testParametersMonotonicAcrossSensitivity() {
        let relaxed = SpeakerSeparationSensitivity.relaxed.parameters
        let balanced = SpeakerSeparationSensitivity.balanced.parameters
        let strict = SpeakerSeparationSensitivity.strict.parameters

        XCTAssertLessThan(
            relaxed.clusteringThreshold,
            balanced.clusteringThreshold,
            "relaxed must use a lower clustering threshold than balanced (more splits)"
        )
        XCTAssertLessThan(
            balanced.clusteringThreshold,
            strict.clusteringThreshold,
            "strict must use a higher clustering threshold than balanced (fewer splits)"
        )

        XCTAssertLessThan(
            relaxed.minSegmentDurationSeconds,
            balanced.minSegmentDurationSeconds,
            "relaxed must accept shorter segments than balanced for embedding"
        )
        XCTAssertLessThan(
            balanced.minSegmentDurationSeconds,
            strict.minSegmentDurationSeconds,
            "strict must require longer segments than balanced for embedding"
        )
    }
}
