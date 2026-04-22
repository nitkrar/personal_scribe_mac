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

    /// Pins the height-banding contract: every pill state's height
    /// comes from `PersonalScribeTheme.Pill.Height` (`resting` / `active` /
    /// `card`), not a loose literal. Failure here = a future edit bumped
    /// one state out of its band and future-you needs to decide whether
    /// the band definition changed or the state was mis-assigned.
    func testPillSizesRespectHeightBands() {
        // Resting band — ambient, non-demanding surfaces.
        XCTAssertEqual(PillOverlayView.idleSize.height, PersonalScribeTheme.Pill.Height.resting)
        XCTAssertEqual(PillOverlayView.doneSize.height, PersonalScribeTheme.Pill.Height.resting)

        // Active band — live session + progress + error.
        XCTAssertEqual(PillOverlayView.holdToRecordSize.height, PersonalScribeTheme.Pill.Height.active)
        XCTAssertEqual(PillOverlayView.recordingSize.height, PersonalScribeTheme.Pill.Height.active)
        XCTAssertEqual(PillOverlayView.transcribingSize.height, PersonalScribeTheme.Pill.Height.active)
        XCTAssertEqual(PillOverlayView.downloadingSize.height, PersonalScribeTheme.Pill.Height.active)
        XCTAssertEqual(PillOverlayView.loadingSize.height, PersonalScribeTheme.Pill.Height.active)
        XCTAssertEqual(PillOverlayView.errorSize.height, PersonalScribeTheme.Pill.Height.active)

        // Card band — cancel card (not a pill).
        XCTAssertEqual(PillOverlayView.cancelCardSize.height, PersonalScribeTheme.Pill.Height.card)
    }

    /// Pins the width-banding contract: every pill state's width comes
    /// from `PersonalScribeTheme.Pill.Width` (`compact` / `snug` /
    /// `medium` / `wide` / `card`), not a loose literal.
    func testPillSizesRespectWidthBands() {
        // Compact band — icon-only ambient surfaces.
        XCTAssertEqual(PillOverlayView.idleSize.width, PersonalScribeTheme.Pill.Width.compact)
        XCTAssertEqual(PillOverlayView.doneSize.width, PersonalScribeTheme.Pill.Width.compact)

        // Medium band — all live-session + informational states.
        XCTAssertEqual(PillOverlayView.holdToRecordSize.width, PersonalScribeTheme.Pill.Width.medium)
        XCTAssertEqual(PillOverlayView.recordingSize.width, PersonalScribeTheme.Pill.Width.medium)
        XCTAssertEqual(PillOverlayView.transcribingSize.width, PersonalScribeTheme.Pill.Width.medium)
        XCTAssertEqual(PillOverlayView.downloadingSize.width, PersonalScribeTheme.Pill.Width.medium)
        XCTAssertEqual(PillOverlayView.loadingSize.width, PersonalScribeTheme.Pill.Width.medium)
        XCTAssertEqual(PillOverlayView.errorSize.width, PersonalScribeTheme.Pill.Width.medium)

        // Card band — cancel card (not a pill).
        XCTAssertEqual(PillOverlayView.cancelCardSize.width, PersonalScribeTheme.Pill.Width.card)
    }
}
