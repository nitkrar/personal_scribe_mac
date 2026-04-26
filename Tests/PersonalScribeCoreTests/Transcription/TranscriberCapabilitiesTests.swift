import XCTest
@testable import PersonalScribeCore

/// #078.2 — `TranscriberCapabilities` is the four-field Bool struct
/// adapters declare per L11 / synthesis decision #1. Tests pin the
/// field set, the all-`false` default, and the two anchor profiles
/// (Parakeet = all four, Qwen3 = none).
final class TranscriberCapabilitiesTests: XCTestCase {
    func testAllFieldsDefaultFalse() {
        // Default initializer means: an adapter that wraps a barebones
        // ASR returning text only can construct a capabilities value
        // without thinking about each field. Default is conservative —
        // features must opt-in explicitly.
        let capabilities = TranscriberCapabilities()

        XCTAssertFalse(capabilities.providesTokenTimings)
        XCTAssertFalse(capabilities.providesConfidence)
        XCTAssertFalse(capabilities.providesPerformanceMetrics)
        XCTAssertFalse(capabilities.providesCustomVocabulary)
    }

    func testParakeetCapabilitiesEnableAllFour() {
        // Parakeet TDT exposes token timings, confidence, perf
        // metrics, and accepts a custom-vocabulary list (per the
        // 2026-04-25 ASR-output-shapes investigation). The adapter
        // (Phase D) declares all four `true`. This pins the anchor.
        let capabilities = TranscriberCapabilities(
            providesTokenTimings: true,
            providesConfidence: true,
            providesPerformanceMetrics: true,
            providesCustomVocabulary: true
        )

        XCTAssertTrue(capabilities.providesTokenTimings)
        XCTAssertTrue(capabilities.providesConfidence)
        XCTAssertTrue(capabilities.providesPerformanceMetrics)
        XCTAssertTrue(capabilities.providesCustomVocabulary)
    }

    func testQwenCapabilitiesAreTextOnly() {
        // Qwen3 ASR returns plain `String` — no metadata, no custom
        // vocab. Default-init produces the correct shape.
        let capabilities = TranscriberCapabilities()

        XCTAssertEqual(
            capabilities,
            TranscriberCapabilities(
                providesTokenTimings: false,
                providesConfidence: false,
                providesPerformanceMetrics: false,
                providesCustomVocabulary: false
            )
        )
    }
}
