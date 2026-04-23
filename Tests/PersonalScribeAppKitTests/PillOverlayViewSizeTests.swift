import XCTest
import PersonalScribeCore
@testable import PersonalScribeAppKit

/// Unit coverage for `PillOverlayView.size(for:)` — the pure helper that
/// maps a `PillOverlayVisibility` to the panel footprint the overlay
/// must render at. Presenter wiring (#044) calls this once per
/// visibility transition and hands the size to
/// `NSPanel.setFrame(_:display:animate:)` so the panel tracks the
/// visible pill's bounds rather than lingering at the fixed 280×60
/// canvas that created the "halo" click-area (#044 repro).
@MainActor
final class PillOverlayViewSizeTests: XCTestCase {
    func testSizeForHiddenIsZero() {
        // `.hidden` doesn't render a pill, so there is no target size.
        // `.zero` (not `nil`) keeps the return type total for callers
        // that still want to pass it to `setFrame`; presenter logic
        // short-circuits on `.hidden` before calling the helper.
        XCTAssertEqual(PillOverlayView.size(for: .hidden), .zero)
    }

    func testSizeForIdleMatchesIdleSize() {
        XCTAssertEqual(PillOverlayView.size(for: .idle), PillOverlayView.idleSize)
    }

    func testSizeForHoldToRecordMatchesHoldSize() {
        XCTAssertEqual(
            PillOverlayView.size(for: .holdToRecord),
            PillOverlayView.holdToRecordSize
        )
    }

    func testSizeForRecordingMatchesRecordingSize() {
        XCTAssertEqual(
            PillOverlayView.size(for: .recording),
            PillOverlayView.recordingSize
        )
    }

    func testSizeForTranscribingMatchesTranscribingSize() {
        XCTAssertEqual(
            PillOverlayView.size(for: .transcribing),
            PillOverlayView.transcribingSize
        )
    }

    func testSizeForDoneMatchesDoneSize() {
        XCTAssertEqual(PillOverlayView.size(for: .done), PillOverlayView.doneSize)
    }

    func testSizeForDownloadingMatchesDownloadingSize() {
        XCTAssertEqual(
            PillOverlayView.size(for: .downloading(fractionCompleted: 0.5)),
            PillOverlayView.downloadingSize
        )
    }

    func testSizeForLoadingMatchesLoadingSize() {
        XCTAssertEqual(PillOverlayView.size(for: .loading), PillOverlayView.loadingSize)
    }

    func testSizeForErrorMatchesErrorSize() {
        XCTAssertEqual(
            PillOverlayView.size(for: .error(message: "boom")),
            PillOverlayView.errorSize
        )
    }

    func testSizeForCancelledMatchesCancelCardSize() {
        // Cancel Card is not a pill but shares the resize path — the
        // panel grows to 280×44 at the same bottom-center anchor.
        XCTAssertEqual(
            PillOverlayView.size(for: .cancelled),
            PillOverlayView.cancelCardSize
        )
    }

}
