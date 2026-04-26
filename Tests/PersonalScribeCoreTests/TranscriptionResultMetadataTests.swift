import XCTest
@testable import PersonalScribeCore

/// #078.3 — `TranscriptionResult` gains optional metadata fields per
/// L11. Adapter declares its `TranscriberCapabilities`; populates the
/// optional fields it advertises; leaves the rest `nil`. Existing
/// call sites compile unchanged because every new field has a `nil`
/// default.
final class TranscriptionResultMetadataTests: XCTestCase {
    func testTranscriptionResultDefaultsAllOptionalMetadataNil() {
        // Construct with only the legacy required parameters. All
        // five new optional fields default to `nil` — the contract
        // every existing caller (today's parakeet adapter, fakes,
        // tests, post-processing) relies on.
        let result = TranscriptionResult(
            text: "hello world",
            audioDuration: .seconds(2),
            processingDuration: .milliseconds(120)
        )

        XCTAssertNil(result.confidence)
        XCTAssertNil(result.tokenTimings)
        XCTAssertNil(result.performanceMetrics)
        XCTAssertNil(result.ctcDetectedTerms)
        XCTAssertNil(result.ctcAppliedTerms)
    }

    func testTokenTimingRoundTripsStartEndConfidence() {
        // `TokenTiming` carries token + start + end + optional
        // confidence. Construct one with all four set, assert the
        // values survive (preserves the field shape).
        let timing = TokenTiming(
            token: "hello",
            start: .milliseconds(100),
            end: .milliseconds(450),
            confidence: 0.92
        )

        XCTAssertEqual(timing.token, "hello")
        XCTAssertEqual(timing.start, .milliseconds(100))
        XCTAssertEqual(timing.end, .milliseconds(450))
        XCTAssertEqual(timing.confidence, 0.92)

        // Confidence is optional — nil round-trip pinned separately
        // so the optional shape is locked.
        let unscored = TokenTiming(
            token: "world",
            start: .milliseconds(500),
            end: .milliseconds(800)
        )
        XCTAssertNil(unscored.confidence)
    }

    func testExistingCallSitesCompileWithNoMetadataChange() {
        // The pre-#078 init signature was
        // `init(text:segments:audioDuration:processingDuration:)`. We
        // pin that the four-arg legacy shape still compiles and the
        // metadata fields remain `nil`. If a future change makes any
        // metadata field non-optional, this call site fails to
        // compile — the load-bearing oracle for "additive only."
        let result = TranscriptionResult(
            text: "legacy",
            segments: [
                TranscriptionResult.Segment(
                    text: "legacy",
                    start: .seconds(0),
                    end: .seconds(1)
                )
            ],
            audioDuration: .seconds(1),
            processingDuration: .milliseconds(50)
        )

        XCTAssertEqual(result.text, "legacy")
        XCTAssertEqual(result.segments.count, 1)
        XCTAssertNil(result.confidence)
        XCTAssertNil(result.tokenTimings)
        XCTAssertNil(result.performanceMetrics)
        XCTAssertNil(result.ctcDetectedTerms)
        XCTAssertNil(result.ctcAppliedTerms)
    }
}
