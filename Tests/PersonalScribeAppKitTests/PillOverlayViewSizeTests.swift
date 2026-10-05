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
        XCTAssertEqual(PillOverlayView.size(for: .hidden, style: .classic), .zero)
    }

    func testSizeForIdleMatchesIdleSize() {
        XCTAssertEqual(
            PillOverlayView.size(for: .idle, style: .classic),
            CGSize(width: 80, height: 28)
        )
    }

    func testSizeForHoldToRecordMatchesHoldSize() {
        XCTAssertEqual(
            PillOverlayView.size(for: .holdToRecord, style: .classic),
            CGSize(width: 220, height: 36)
        )
    }

    func testSizeForRecordingMatchesRecordingSize() {
        XCTAssertEqual(
            PillOverlayView.size(for: .recording, style: .classic),
            CGSize(width: 220, height: 36)
        )
    }

    func testMiniIdleAndRecordingSizesMatchMockupAtRestAndHover() {
        XCTAssertEqual(
            PillOverlayView.size(for: .idle, style: .mini, isHovered: false),
            CGSize(width: 40, height: 16)
        )
        XCTAssertEqual(
            PillOverlayView.size(for: .idle, style: .mini, isHovered: true),
            CGSize(width: 66, height: 30)
        )
        XCTAssertEqual(
            PillOverlayView.size(for: .recording, style: .mini, isHovered: false),
            CGSize(width: 110, height: 20)
        )
        XCTAssertEqual(
            PillOverlayView.size(for: .recording, style: .mini, isHovered: true),
            CGSize(width: 170, height: 30)
        )
    }

    func testIdleHoverKeepsItsFootprintAndCentersTheOnlyRecordButton() {
        for style in [PillStyle.mini, .classic] {
            let recordOnly = PillIdleControlsLayout(
                metrics: style.metrics,
                showsModeButton: false
            )
            let twoButtons = PillIdleControlsLayout(
                metrics: style.metrics,
                showsModeButton: true
            )

            XCTAssertEqual(recordOnly.size, twoButtons.size)
            XCTAssertEqual(
                recordOnly.size,
                PillOverlayView.size(for: .idle, style: style, isHovered: true)
            )
            XCTAssertNil(recordOnly.modeFrame)
            XCTAssertEqual(recordOnly.recordFrame.midX, recordOnly.size.width / 2)
            XCTAssertEqual(recordOnly.recordFrame.midY, recordOnly.size.height / 2)
        }
    }

    func testPausedSizesMatchMockup() {
        XCTAssertEqual(
            PillOverlayView.size(for: .paused(elapsedSeconds: 23), style: .classic),
            CGSize(width: 220, height: 36)
        )
        XCTAssertEqual(
            PillOverlayView.size(for: .paused(elapsedSeconds: 23), style: .mini),
            CGSize(width: 170, height: 30)
        )
    }

    func testSizeForTranscribingMatchesTranscribingSize() {
        XCTAssertEqual(
            PillOverlayView.size(for: .transcribing, style: .classic),
            PillOverlayView.size(for: .recording, style: .classic)
        )
        XCTAssertEqual(
            PillOverlayView.size(for: .transcribing, style: .mini),
            CGSize(width: 110, height: 20)
        )
        XCTAssertEqual(
            PillOverlayView.size(for: .transcribing, style: .mini),
            PillOverlayView.size(for: .recording, style: .mini)
        )
    }

    func testSizeForDownloadingMatchesDownloadingSize() {
        XCTAssertEqual(
            PillOverlayView.size(
                for: .downloading(fractionCompleted: 0.5),
                style: .classic
            ),
            CGSize(width: 220, height: 36)
        )
    }

    func testSizeForLoadingMatchesLoadingSize() {
        XCTAssertEqual(
            PillOverlayView.size(for: .loading, style: .classic),
            CGSize(width: 220, height: 36)
        )
    }

    func testSizeForErrorMatchesErrorSize() {
        XCTAssertEqual(
            PillOverlayView.size(for: .error(message: "boom"), style: .classic),
            CGSize(width: 220, height: 36)
        )
    }

    func testSizeForCancelledMatchesCancelCardSize() {
        // Cancel Card is not a pill but shares the resize path — the
        // panel grows to 264×36 at the same bottom-center anchor.
        XCTAssertEqual(
            PillOverlayView.size(for: .cancelled, style: .classic),
            PillOverlayView.cancelCardSize
        )
    }

}
