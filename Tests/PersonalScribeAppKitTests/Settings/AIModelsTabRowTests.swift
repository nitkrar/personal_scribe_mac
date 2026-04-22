import XCTest
import SwiftUI
@testable import PersonalScribeAppKit
@testable import PersonalScribeCore

/// Tests for `ModelRow` — the per-row presenter used by AIModelsTab
/// (Stage A step 3.2). The SwiftUI body is unit-untestable, but the
/// chip derivation + size formatting are pure functions of the injected
/// state. Manual verification of the rendered tab lives in
/// `Tests/PersonalScribeAppKitTests/ManualSettingsVerification.md`
/// under the `AI Models tab — Stage A (step 3.2)` section.
@MainActor
final class AIModelsTabRowTests: XCTestCase {
    private func row(
        state: ModelDownloadState?,
        isActive: Bool = false,
        descriptor: ModelDescriptor = BuiltInModelCatalog.parakeetTDT06Bv2
    ) -> ModelRow {
        ModelRow(
            descriptor: descriptor,
            state: state,
            isActive: isActive,
            onActivate: {}
        )
    }

    func testChipForNilStateShowsNotDownloadedNeutral() {
        let r = row(state: nil)
        XCTAssertEqual(r.chip.label, "Not downloaded")
        XCTAssertEqual(r.chip.status, .neutral)
    }

    func testChipForDownloadingUsesWarningStatusAndPercentLabel() {
        let state = ModelDownloadState(
            descriptorId: BuiltInModelCatalog.parakeetTDT06Bv2.id,
            phase: .downloading,
            fractionCompleted: 0.42
        )
        let r = row(state: state)
        XCTAssertEqual(r.chip.status, .warning)
        XCTAssertEqual(r.chip.label, "Downloading 42%")
    }

    func testChipForLoadingUsesWarningStatus() {
        let state = ModelDownloadState(
            descriptorId: BuiltInModelCatalog.parakeetTDT06Bv2.id,
            phase: .loading,
            fractionCompleted: 1
        )
        let r = row(state: state)
        XCTAssertEqual(r.chip.status, .warning)
        XCTAssertEqual(r.chip.label, "Loading…")
    }

    func testChipForReadyActiveUsesReadyStatusAndActiveLabel() {
        let state = ModelDownloadState(
            descriptorId: BuiltInModelCatalog.parakeetTDT06Bv2.id,
            phase: .ready,
            fractionCompleted: 1
        )
        let r = row(state: state, isActive: true)
        XCTAssertEqual(r.chip.status, .ready)
        XCTAssertEqual(r.chip.label, "Active")
    }

    func testChipForReadyInactiveUsesReadyStatusAndReadyLabel() {
        let state = ModelDownloadState(
            descriptorId: BuiltInModelCatalog.parakeetTDT06Bv2.id,
            phase: .ready,
            fractionCompleted: 1
        )
        let r = row(state: state, isActive: false)
        XCTAssertEqual(r.chip.status, .ready)
        XCTAssertEqual(r.chip.label, "Ready")
    }

    func testChipForFailedUsesFailedStatusAndTruncatedMessage() {
        let longMessage = String(repeating: "x", count: 80)
        let state = ModelDownloadState(
            descriptorId: BuiltInModelCatalog.parakeetTDT06Bv2.id,
            phase: .failed(message: longMessage),
            fractionCompleted: 0
        )
        let r = row(state: state)
        XCTAssertEqual(r.chip.status, .failed)
        XCTAssertTrue(r.chip.label.hasPrefix("Failed: "))
        XCTAssertTrue(r.chip.label.hasSuffix("…"), "Expected long failure messages to be truncated; got \(r.chip.label)")
    }

}
