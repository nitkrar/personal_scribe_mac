import XCTest
@testable import PersonalScribeCore

/// Tests for `DefaultModelSelectionPolicy` — picks the first-launch
/// default voice model based on the machine's physical RAM. Low-RAM
/// machines (≤ 8 GB, i.e. below the 10 GiB threshold) get the
/// lightweight CTC-110M variant; everyone else gets the baseline.
///
/// Ticket #016 (reframed to RAM-aware selection).
final class DefaultModelSelectionPolicyTests: XCTestCase {
    // MARK: - Fixtures

    private let lightweight = BuiltInModelCatalog.parakeetTDTCTC110M  // 110M params
    private let baseline = BuiltInModelCatalog.parakeetTDT06Bv2       // 600M params

    private let eightGiB: Int64 = 8 * 1024 * 1024 * 1024
    private let tenGiB: Int64 = 10 * 1024 * 1024 * 1024
    private let sixteenGiB: Int64 = 16 * 1024 * 1024 * 1024

    // MARK: - Threshold

    func testEightGiBMachineFallsBelowThresholdAndPicksLightweight() {
        let pick = DefaultModelSelectionPolicy.recommendedDefault(
            physicalMemoryBytes: eightGiB,
            registeredModels: BuiltInModelCatalog.registeredModels,
            baselineDefault: baseline
        )
        XCTAssertEqual(pick.id, lightweight.id)
    }

    func testSixteenGiBMachineSitsAboveThresholdAndPicksBaseline() {
        let pick = DefaultModelSelectionPolicy.recommendedDefault(
            physicalMemoryBytes: sixteenGiB,
            registeredModels: BuiltInModelCatalog.registeredModels,
            baselineDefault: baseline
        )
        XCTAssertEqual(pick.id, baseline.id)
    }

    /// Exactly-on-threshold → not below → baseline wins. Guards
    /// against off-by-one drift if someone later bumps the threshold.
    func testExactlyAtThresholdPicksBaseline() {
        let pick = DefaultModelSelectionPolicy.recommendedDefault(
            physicalMemoryBytes: tenGiB,
            registeredModels: BuiltInModelCatalog.registeredModels,
            baselineDefault: baseline
        )
        XCTAssertEqual(pick.id, baseline.id)
    }

    func testZeroPhysicalMemoryStillPicksLightweight() {
        // Defensive path — if ProcessInfo reports 0 (shouldn't happen
        // in practice but could on unusual hosts), treat as low-RAM
        // rather than silently pick the heavy default. A 110M model
        // that fits is better than a 600M model that OOMs.
        let pick = DefaultModelSelectionPolicy.recommendedDefault(
            physicalMemoryBytes: 0,
            registeredModels: BuiltInModelCatalog.registeredModels,
            baselineDefault: baseline
        )
        XCTAssertEqual(pick.id, lightweight.id)
    }

    // MARK: - Candidate selection

    /// When the threshold is crossed, the policy picks the registered
    /// model with the lowest parameterCount (not the baseline).
    /// Tiebreaker is approximateSizeBytes.
    func testLowMemoryPicksLowestParameterCountFromRegistered() {
        let pick = DefaultModelSelectionPolicy.recommendedDefault(
            physicalMemoryBytes: eightGiB,
            registeredModels: [
                BuiltInModelCatalog.parakeetTDT06Bv2,   // 600M
                BuiltInModelCatalog.parakeetTDTCTC110M, // 110M ← winner
                BuiltInModelCatalog.parakeetTDT06Bv3,   // 600M
            ],
            baselineDefault: baseline
        )
        XCTAssertEqual(pick.id, BuiltInModelCatalog.parakeetTDTCTC110M.id)
    }

    /// If the registered list contains nothing lighter than the
    /// baseline, the policy falls back to the baseline — avoids
    /// returning a model that's *heavier* than the baseline just
    /// because it's technically different.
    func testNoLighterCandidateAvailableFallsBackToBaseline() {
        let pick = DefaultModelSelectionPolicy.recommendedDefault(
            physicalMemoryBytes: eightGiB,
            registeredModels: [
                BuiltInModelCatalog.parakeetTDT06Bv2,
                BuiltInModelCatalog.parakeetTDT06Bv3,
            ],
            baselineDefault: baseline
        )
        XCTAssertEqual(pick.id, baseline.id)
    }

    /// Empty registry → no candidate to recommend → baseline.
    /// Defensive: should never happen in production but guards against
    /// catalog-init ordering bugs.
    func testEmptyRegisteredModelsReturnsBaseline() {
        let pick = DefaultModelSelectionPolicy.recommendedDefault(
            physicalMemoryBytes: eightGiB,
            registeredModels: [],
            baselineDefault: baseline
        )
        XCTAssertEqual(pick.id, baseline.id)
    }

    /// If a lightweight candidate exists but omits parameterCount,
    /// it's not eligible — the policy won't pick an unmeasured model
    /// over a well-characterized baseline.
    func testCandidateWithoutParameterCountIsNotEligible() {
        let unmeasured = ModelDescriptor(
            id: "unmeasured",
            displayName: "Unmeasured",
            shortDescription: "No benchmarks declared.",
            architecture: "Test",
            repository: "example/unmeasured",
            revision: "abc12345",
            requiredRelativePaths: [],
            approximateSizeBytes: 100_000_000,
            engine: .parakeetTDT
            // No performance ratings — parameterCount is nil.
        )
        let pick = DefaultModelSelectionPolicy.recommendedDefault(
            physicalMemoryBytes: eightGiB,
            registeredModels: [unmeasured, baseline],
            baselineDefault: baseline
        )
        XCTAssertEqual(pick.id, baseline.id)
    }
}
