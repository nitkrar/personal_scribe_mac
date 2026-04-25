import XCTest
@testable import PersonalScribeAppKit
@testable import PersonalScribeCore

/// Tests for `ModelInfoPopoverPresenter` — the pure presenter that
/// maps a `ModelDescriptor` (in the context of all registered
/// siblings) into the info-popover's rendered sections.
///
/// The SwiftUI body is unit-untestable; these tests pin everything
/// the view reads off the presenter, including the computed-relative
/// ranking invariants that determine which bucket each descriptor
/// falls into on the Speed / Accuracy bars.
@MainActor
final class ModelInfoPopoverPresenterTests: XCTestCase {
    private func registeredSiblings() -> [ModelDescriptor] {
        BuiltInModelCatalog.registeredModels
    }

    private func presenter(
        for descriptor: ModelDescriptor,
        siblings: [ModelDescriptor]? = nil
    ) -> ModelInfoPopoverPresenter {
        ModelInfoPopoverPresenter(
            descriptor: descriptor,
            siblings: siblings ?? registeredSiblings()
        )
    }

    // MARK: - Header

    func testTitleMatchesDescriptorDisplayName() {
        XCTAssertEqual(
            presenter(for: BuiltInModelCatalog.parakeetTDT06Bv2).title,
            BuiltInModelCatalog.parakeetTDT06Bv2.displayName
        )
    }

    func testSubtitleMatchesDescriptorShortDescription() {
        XCTAssertEqual(
            presenter(for: BuiltInModelCatalog.parakeetTDT06Bv2).subtitle,
            BuiltInModelCatalog.parakeetTDT06Bv2.shortDescription
        )
    }

    // MARK: - Rating rows (computed-relative)

    func testSpeedRowLabelsCTCAsFastestWithFullBar() {
        let p = presenter(for: BuiltInModelCatalog.parakeetTDTCTC110M)
        guard let row = p.speedRow else { return XCTFail("Expected speedRow") }
        XCTAssertEqual(row.title, "Speed")
        XCTAssertEqual(row.label, "Fastest")
        XCTAssertEqual(row.filledSegments, 3)
        XCTAssertEqual(row.totalSegments, 3)
    }

    func testSpeedRowLabelsV2AsFastWithTwoSegments() {
        let p = presenter(for: BuiltInModelCatalog.parakeetTDT06Bv2)
        guard let row = p.speedRow else { return XCTFail("Expected speedRow") }
        XCTAssertEqual(row.label, "Fast")
        XCTAssertEqual(row.filledSegments, 2)
    }

    func testSpeedRowLabelsV3AsSlowWithOneSegment() {
        let p = presenter(for: BuiltInModelCatalog.parakeetTDT06Bv3)
        guard let row = p.speedRow else { return XCTFail("Expected speedRow") }
        XCTAssertEqual(row.label, "Slow")
        XCTAssertEqual(row.filledSegments, 1)
    }

    func testAccuracyRowLabelsV2AsHighWithFullBar() {
        let p = presenter(for: BuiltInModelCatalog.parakeetTDT06Bv2)
        guard let row = p.accuracyRow else { return XCTFail("Expected accuracyRow") }
        XCTAssertEqual(row.title, "Accuracy")
        XCTAssertEqual(row.label, "High")
        XCTAssertEqual(row.filledSegments, 3)
    }

    func testAccuracyRowLabelsV3AsMediumWithTwoSegments() {
        let p = presenter(for: BuiltInModelCatalog.parakeetTDT06Bv3)
        guard let row = p.accuracyRow else { return XCTFail("Expected accuracyRow") }
        XCTAssertEqual(row.label, "Medium")
        XCTAssertEqual(row.filledSegments, 2)
    }

    func testAccuracyRowLabelsCTCAsLowWithOneSegment() {
        let p = presenter(for: BuiltInModelCatalog.parakeetTDTCTC110M)
        guard let row = p.accuracyRow else { return XCTFail("Expected accuracyRow") }
        XCTAssertEqual(row.label, "Low")
        XCTAssertEqual(row.filledSegments, 1)
    }

    /// When a descriptor omits benchmarks (ad-hoc test fixtures,
    /// hypothetical future catalog entries) the presenter must return
    /// nil rather than guess. The view skips the row in that case.
    func testRatingRowsAreNilWhenDescriptorHasNoBenchmarks() {
        let descriptor = ModelDescriptor(
            id: "no-benchmarks",
            displayName: "No Benchmarks",
            shortDescription: "Fixture without benchmarks.",
            architecture: "Test",
            repository: "example/no-benchmarks",
            revision: "abc123",
            requiredRelativePaths: [],
            approximateSizeBytes: 1,
            engine: .parakeetTDT
        )
        let p = presenter(for: descriptor, siblings: [descriptor])
        XCTAssertNil(p.speedRow)
        XCTAssertNil(p.accuracyRow)
    }

    /// Solo descriptor in its siblings list lands in the top tier
    /// (nothing to rank against). "Fastest / High" + full bar.
    func testSingleSiblingLandsInTopTier() {
        let descriptor = BuiltInModelCatalog.parakeetTDT06Bv2
        let p = presenter(for: descriptor, siblings: [descriptor])
        XCTAssertEqual(p.speedRow?.label, "Fastest")
        XCTAssertEqual(p.speedRow?.filledSegments, 3)
        XCTAssertEqual(p.accuracyRow?.label, "High")
        XCTAssertEqual(p.accuracyRow?.filledSegments, 3)
    }

    /// When the presenter's descriptor isn't in the siblings array,
    /// it should still rank correctly (presenter inserts self to
    /// guard against programmer error).
    func testDescriptorNotInSiblingsStillRanks() {
        let p = presenter(
            for: BuiltInModelCatalog.parakeetTDTCTC110M,
            siblings: [
                BuiltInModelCatalog.parakeetTDT06Bv2,
                BuiltInModelCatalog.parakeetTDT06Bv3,
            ]
        )
        XCTAssertEqual(p.speedRow?.label, "Fastest")
    }

    /// Siblings with missing benchmarks don't participate in ranking —
    /// the presenter ranks the current descriptor among siblings
    /// that have the same metric.
    func testRankingIgnoresSiblingsMissingMetric() {
        let target = BuiltInModelCatalog.parakeetTDTCTC110M
        let mystery = ModelDescriptor(
            id: "mystery",
            displayName: "Mystery",
            shortDescription: "No benchmarks.",
            architecture: "Test",
            repository: "example/mystery",
            revision: "xyz",
            requiredRelativePaths: [],
            approximateSizeBytes: 1,
            engine: .parakeetTDT
        )
        let p = presenter(
            for: target,
            siblings: [target, mystery]
        )
        // CTC is the only sibling with rtfx → top tier.
        XCTAssertEqual(p.speedRow?.label, "Fastest")
        XCTAssertEqual(p.speedRow?.filledSegments, 3)
    }

    // MARK: - Size

    func testSizeValueFormatsBytesAsHumanReadable() {
        let p = presenter(for: BuiltInModelCatalog.parakeetTDT06Bv2)
        XCTAssertTrue(
            p.sizeValue.contains("MB") || p.sizeValue.contains("GB"),
            "Unexpected formatted size: \(p.sizeValue)"
        )
    }

    // MARK: - Detail rows

    func testDetailRowsContainArchitectureRepositoryAndRevisionAsPrefix() {
        let p = presenter(for: BuiltInModelCatalog.parakeetTDT06Bv2)
        XCTAssertEqual(
            Array(p.detailRows.map(\.title).prefix(3)),
            ["Architecture", "Repository", "Revision"]
        )
    }

    func testDetailArchitectureReadsFromDescriptorFieldNotEngineEnum() {
        let p = presenter(for: BuiltInModelCatalog.parakeetTDTCTC110M)
        let archRow = p.detailRows.first(where: { $0.title == "Architecture" })
        XCTAssertEqual(archRow?.value, "Hybrid FastConformer-TDT-CTC")
    }

    func testDetailRevisionIsTruncatedToShortCommitSHA() {
        let p = presenter(for: BuiltInModelCatalog.parakeetTDT06Bv2)
        let revisionRow = p.detailRows.first(where: { $0.title == "Revision" })
        XCTAssertEqual(revisionRow?.value.count, 8)
    }

    func testDetailRepositoryMatchesDescriptor() {
        let p = presenter(for: BuiltInModelCatalog.parakeetTDTCTC110M)
        let repoRow = p.detailRows.first(where: { $0.title == "Repository" })
        XCTAssertEqual(
            repoRow?.value,
            BuiltInModelCatalog.parakeetTDTCTC110M.repository
        )
    }

    /// Parameter count, when present, joins the detail rows.
    func testDetailRowsIncludeParameterCountWhenPresent() {
        let p = presenter(for: BuiltInModelCatalog.parakeetTDTCTC110M)
        let paramRow = p.detailRows.first(where: { $0.title == "Parameters" })
        XCTAssertEqual(paramRow?.value, "110M")
    }

    /// Parameter count row is omitted when the metric isn't declared —
    /// the row isn't inferred from other fields.
    func testDetailRowsOmitParameterCountWhenAbsent() {
        let descriptor = ModelDescriptor(
            id: "no-params",
            displayName: "No Params",
            shortDescription: "Fixture.",
            architecture: "Test",
            repository: "example/no-params",
            revision: "abcdef12",
            requiredRelativePaths: [],
            approximateSizeBytes: 1,
            engine: .parakeetTDT
        )
        let p = presenter(for: descriptor, siblings: [descriptor])
        XCTAssertFalse(p.detailRows.contains(where: { $0.title == "Parameters" }))
    }

    // MARK: - Human-friendly rows

    /// Catalog models declare all four optional fields; all four rows
    /// plus the derived "Model type" row must appear.
    func testHumanFriendlyRowsIncludeAllFiveRowsForCatalogModel() {
        let p = presenter(for: BuiltInModelCatalog.parakeetTDT06Bv2)
        let titles = p.humanFriendlyRows.map(\.title)
        XCTAssertTrue(titles.contains("Made by"),    "Missing 'Made by' row")
        XCTAssertTrue(titles.contains("Works with"), "Missing 'Works with' row")
        XCTAssertTrue(titles.contains("Good for"),   "Missing 'Good for' row")
        XCTAssertTrue(titles.contains("Model type"), "Missing 'Model type' row")
        XCTAssertTrue(titles.contains("License"),    "Missing 'License' row")
    }

    func testHumanFriendlyMadeByMatchesCatalog() {
        let p = presenter(for: BuiltInModelCatalog.parakeetTDT06Bv2)
        let row = p.humanFriendlyRows.first(where: { $0.title == "Made by" })
        XCTAssertEqual(row?.value, "NVIDIA · FluidInference")
    }

    func testHumanFriendlyWorksWithIsMultilingualForV3() {
        let p = presenter(for: BuiltInModelCatalog.parakeetTDT06Bv3)
        let row = p.humanFriendlyRows.first(where: { $0.title == "Works with" })
        XCTAssertEqual(row?.value, "25 European languages")
    }

    func testHumanFriendlyLicenseIsApacheForV3() {
        let p = presenter(for: BuiltInModelCatalog.parakeetTDT06Bv3)
        let row = p.humanFriendlyRows.first(where: { $0.title == "License" })
        XCTAssertEqual(row?.value, "Apache 2.0")
    }

    /// Ad-hoc fixture with no optional fields — only the derived
    /// "Model type" row should appear.
    func testHumanFriendlyRowsContainOnlyModelTypeWhenNoOptionalFields() {
        let descriptor = ModelDescriptor(
            id: "bare",
            displayName: "Bare",
            shortDescription: "No optional fields.",
            architecture: "Test",
            repository: "example/bare",
            revision: "00000000",
            requiredRelativePaths: [],
            approximateSizeBytes: 1,
            engine: .parakeetTDT
        )
        let p = presenter(for: descriptor, siblings: [descriptor])
        XCTAssertEqual(p.humanFriendlyRows.map(\.title), ["Model type"])
    }

    func testModelTypeLabelForASRIsVoiceOffline() {
        let p = presenter(for: BuiltInModelCatalog.parakeetTDT06Bv2)
        let row = p.humanFriendlyRows.first(where: { $0.title == "Model type" })
        XCTAssertEqual(row?.value, "Voice · Offline")
    }
}
