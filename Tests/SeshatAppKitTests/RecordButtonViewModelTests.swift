import XCTest
import SeshatCore
@testable import SeshatAppKit

@MainActor
final class RecordButtonViewModelTests: XCTestCase {
    func testIdleStateMapsToRecordButton() {
        let viewModel = RecordButtonViewModel.make(from: .idle)

        XCTAssertEqual(viewModel.title, "Record")
        XCTAssertEqual(viewModel.systemImageName, "mic.circle.fill")
        XCTAssertTrue(viewModel.isEnabled)
        XCTAssertFalse(viewModel.usesDestructiveRole)
    }

    func testRecordingStateMapsToStopButton() {
        let viewModel = RecordButtonViewModel.make(from: .recording)

        XCTAssertEqual(viewModel.title, "Stop")
        XCTAssertEqual(viewModel.systemImageName, "stop.circle.fill")
        XCTAssertTrue(viewModel.isEnabled)
        XCTAssertTrue(viewModel.usesDestructiveRole)
    }

    func testTranscribingStateMapsToBusyDisabledButton() {
        let viewModel = RecordButtonViewModel.make(from: .transcribing)

        XCTAssertEqual(viewModel.title, "Transcribing…")
        XCTAssertEqual(viewModel.systemImageName, "waveform.circle.fill")
        XCTAssertFalse(viewModel.isEnabled)
        XCTAssertFalse(viewModel.usesDestructiveRole)
    }

    func testErrorStateMapsToRecordAgainButton() {
        let viewModel = RecordButtonViewModel.make(from: .error(.invalidState))

        XCTAssertEqual(viewModel.title, "Record Again")
        XCTAssertEqual(viewModel.systemImageName, "arrow.clockwise.circle.fill")
        XCTAssertTrue(viewModel.isEnabled)
        XCTAssertFalse(viewModel.usesDestructiveRole)
    }
}
