import Combine
import XCTest
import PersonalScribeCore
@testable import PersonalScribeAppKit

@MainActor
final class PillOverlayViewModelTests: XCTestCase {
    func testInitialVisibilityIsIdle() {
        let viewModel = PillOverlayViewModel()

        XCTAssertEqual(viewModel.visibility, .idle)
    }

    func testInitialVisibilityModeDefaultsToAutoShow() {
        // Sprint 2 Lane B1 — auto-show is the mockup-default row.
        let viewModel = PillOverlayViewModel()
        XCTAssertEqual(viewModel.visibilityMode, .autoShow)
    }

    func testIdleSessionMapsToHiddenInAutoShow() {
        let viewModel = PillOverlayViewModel()

        viewModel.apply(sessionState: .idle, preparationProgress: nil)

        // Auto-show default: idle session when there's no download/loading
        // means the pill stays hidden (Mode 2 row — "Pill hidden at rest").
        XCTAssertEqual(viewModel.visibility, .hidden)
    }

    func testRecordingMapsToRecording() {
        let viewModel = PillOverlayViewModel()

        viewModel.apply(sessionState: .capturing, preparationProgress: nil)

        XCTAssertEqual(viewModel.visibility, .recording)
    }

    func testTranscribingMapsToTranscribing() {
        let viewModel = PillOverlayViewModel()

        viewModel.apply(sessionState: .transcribing, preparationProgress: nil)

        XCTAssertEqual(viewModel.visibility, .transcribing)
    }

    func testErrorSessionStateFallsBackToIdleVisibility() {
        let autoShow = PillOverlayViewModel()
        autoShow.apply(sessionState: .error(.audioEngineFailure), preparationProgress: nil)
        XCTAssertEqual(autoShow.visibility, .hidden)

        let alwaysOn = PillOverlayViewModel(visibilityMode: .alwaysOn)
        alwaysOn.apply(sessionState: .error(.resampleFailure), preparationProgress: nil)
        XCTAssertEqual(alwaysOn.visibility, .idle)
    }

    func testDownloadingProgressOverridesIdleState() {
        let viewModel = PillOverlayViewModel()
        let progress = ModelDownloadProgress(
            phase: .downloading,
            fractionCompleted: 0.42,
            receivedBytes: 42,
            expectedBytes: 100
        )

        viewModel.apply(sessionState: .idle, preparationProgress: progress)

        XCTAssertEqual(viewModel.visibility, .downloading(fractionCompleted: 0.42))
    }

    func testFinishedDownloadHidesPillInAutoShow() {
        let viewModel = PillOverlayViewModel()
        let progress = ModelDownloadProgress(
            phase: .finished,
            fractionCompleted: 1.0,
            receivedBytes: 100,
            expectedBytes: 100
        )

        viewModel.apply(sessionState: .idle, preparationProgress: progress)

        // Auto-show: finished download + idle session → pill fades out.
        XCTAssertEqual(viewModel.visibility, .hidden)
    }

    func testLoadingProgressMapsToLoadingPill() {
        let viewModel = PillOverlayViewModel()
        let progress = ModelDownloadProgress(
            phase: .loading,
            fractionCompleted: 1.0,
            receivedBytes: 0,
            expectedBytes: nil
        )

        viewModel.apply(sessionState: .idle, preparationProgress: progress)

        XCTAssertEqual(viewModel.visibility, .loading)
    }

    func testRecordingStateKeepsRecordingVisibleDuringDownload() {
        let viewModel = PillOverlayViewModel()
        let progress = ModelDownloadProgress(
            phase: .downloading,
            fractionCompleted: 0.42,
            receivedBytes: 42,
            expectedBytes: 100
        )

        viewModel.apply(sessionState: .capturing, preparationProgress: progress)

        XCTAssertEqual(viewModel.visibility, .recording)
    }

    func testTranscribingShowsLoadingWhenModelIsStillLoading() {
        let viewModel = PillOverlayViewModel()
        let progress = ModelDownloadProgress(
            phase: .loading,
            fractionCompleted: 1.0,
            receivedBytes: 0,
            expectedBytes: nil
        )

        viewModel.apply(sessionState: .transcribing, preparationProgress: progress)

        XCTAssertEqual(viewModel.visibility, .loading)
    }

    // MARK: - Visibility mode interactions (Sprint 2 Lane B1)

    func testAlwaysOnModeShowsIdlePillWhenSessionIsIdle() {
        let viewModel = PillOverlayViewModel(visibilityMode: .alwaysOn)

        viewModel.apply(sessionState: .idle, preparationProgress: nil)

        // Mode 1 row ("Always On") — idle pill visible at rest.
        XCTAssertEqual(viewModel.visibility, .idle)
    }

    func testAlwaysOnModeShowsRecordingWhenRecording() {
        let viewModel = PillOverlayViewModel(visibilityMode: .alwaysOn)

        viewModel.apply(sessionState: .capturing, preparationProgress: nil)

        XCTAssertEqual(viewModel.visibility, .recording)
    }

    func testAutoShowModeHidesPillWhenIdleAndNoPreparation() {
        let viewModel = PillOverlayViewModel(visibilityMode: .autoShow)

        viewModel.apply(sessionState: .idle, preparationProgress: nil)

        XCTAssertEqual(viewModel.visibility, .hidden,
                       "Auto-show: idle session + no prep = no pill")
    }

    func testAutoShowModeShowsDownloadingProgressEvenAtRest() {
        let viewModel = PillOverlayViewModel(visibilityMode: .autoShow)
        let progress = ModelDownloadProgress(
            phase: .downloading,
            fractionCompleted: 0.25,
            receivedBytes: 25,
            expectedBytes: 100
        )

        viewModel.apply(sessionState: .idle, preparationProgress: progress)

        XCTAssertEqual(viewModel.visibility, .downloading(fractionCompleted: 0.25))
    }

    func testSetVisibilityModeReevaluatesVisibilityImmediately() {
        let viewModel = PillOverlayViewModel(visibilityMode: .alwaysOn)
        viewModel.apply(sessionState: .idle, preparationProgress: nil)
        XCTAssertEqual(viewModel.visibility, .idle)

        viewModel.setVisibilityMode(.autoShow)
        XCTAssertEqual(viewModel.visibilityMode, .autoShow)
        XCTAssertEqual(viewModel.visibility, .idle)

        viewModel.apply(sessionState: .idle, preparationProgress: nil)
        XCTAssertEqual(viewModel.visibility, .hidden)

        viewModel.setVisibilityMode(.alwaysOn)
        XCTAssertEqual(viewModel.visibilityMode, .alwaysOn)
        XCTAssertEqual(viewModel.visibility, .hidden)

        viewModel.apply(sessionState: .idle, preparationProgress: nil)
        XCTAssertEqual(viewModel.visibility, .idle)
    }

    func testTransitionSequenceIdleRecordingTranscribingIdleError() async {
        // Compatibility mode follows the AppStore mapping: success still
        // shows `.done`, but an error falls back to the mode's idle
        // visibility instead of surfacing a pill error state.
        //   recording → transcribing → done → idle
        let viewModel = PillOverlayViewModel(visibilityMode: .alwaysOn)
        var emitted: [PillOverlayViewModel.Visibility] = []
        let expectation = expectation(description: "Collect published visibility updates")
        var cancellable: AnyCancellable?

        cancellable = viewModel.$visibility
            .dropFirst()
            .sink { value in
                emitted.append(value)

                if emitted.count == 4 {
                    expectation.fulfill()
                }
            }

        viewModel.apply(sessionState: .capturing, preparationProgress: nil)
        viewModel.apply(sessionState: .transcribing, preparationProgress: nil)
        viewModel.apply(sessionState: .idle, preparationProgress: nil)
        viewModel.apply(sessionState: .error(.audioEngineFailure), preparationProgress: nil)

        await fulfillment(of: [expectation], timeout: 1.0)
        withExtendedLifetime(cancellable) {}

        XCTAssertEqual(viewModel.visibility, .idle)
        XCTAssertEqual(
            emitted,
            [.recording, .transcribing, .done, .idle]
        )
    }

    func testTranscribingToIdleShowsDoneConfirmation() {
        // Core semantics of the `.done` transient state: when the
        // session transitions transcribing → idle (success path),
        // the view model emits `.done` immediately so the pill can
        // show a checkmark. The done task then falls through to the
        // mode's normal idle after `doneConfirmationDuration`.
        let viewModel = PillOverlayViewModel(visibilityMode: .autoShow)

        viewModel.apply(sessionState: .capturing, preparationProgress: nil)
        XCTAssertEqual(viewModel.visibility, .recording)

        viewModel.apply(sessionState: .transcribing, preparationProgress: nil)
        XCTAssertEqual(viewModel.visibility, .transcribing)

        viewModel.apply(sessionState: .idle, preparationProgress: nil)
        XCTAssertEqual(viewModel.visibility, .done)
    }

    func testNewRecordingPreemptsDoneConfirmation() {
        // If the user triggers a fresh recording while the previous
        // `.done` confirmation is still on screen, the new recording
        // wins — the done task is cancelled and `.recording` replaces
        // `.done` without waiting out the timer.
        let viewModel = PillOverlayViewModel(visibilityMode: .autoShow)

        viewModel.apply(sessionState: .transcribing, preparationProgress: nil)
        viewModel.apply(sessionState: .idle, preparationProgress: nil)
        XCTAssertEqual(viewModel.visibility, .done)

        viewModel.apply(sessionState: .capturing, preparationProgress: nil)
        XCTAssertEqual(viewModel.visibility, .recording)
    }

    // MARK: - Phase 1: holdToRecord + cancelled state machine

    func testApplyHoldToRecordVisibilitySetsVisibility() {
        let viewModel = PillOverlayViewModel()

        viewModel.apply(visibility: .holdToRecord)

        XCTAssertEqual(viewModel.visibility, .holdToRecord)
    }

    func testApplyCancelledVisibilitySetsVisibility() {
        let viewModel = PillOverlayViewModel()

        viewModel.apply(visibility: .cancelled)

        XCTAssertEqual(viewModel.visibility, .cancelled)
    }

    func testIsAudioActiveTrueForHoldToRecord() {
        // Per pill UX spec §3: opt+/ key-down while idle enters
        // holdToRecord AND begins microphone capture. The view model's
        // `isAudioActive` flag must reflect that so the waveform
        // renders during hold.
        let viewModel = PillOverlayViewModel()

        viewModel.apply(visibility: .holdToRecord)

        XCTAssertTrue(viewModel.isAudioActive)
    }

    func testIsAudioActiveTrueForRecording() {
        // Regression: existing contract for committed recording.
        let viewModel = PillOverlayViewModel()

        viewModel.apply(visibility: .recording)

        XCTAssertTrue(viewModel.isAudioActive)
    }

    func testIsAudioActiveFalseForCancelled() {
        let viewModel = PillOverlayViewModel()

        viewModel.apply(visibility: .cancelled)

        XCTAssertFalse(viewModel.isAudioActive)
    }

    func testIsAudioActiveFalseForIdleHiddenTranscribingDone() {
        let viewModel = PillOverlayViewModel()

        for state: PillOverlayViewModel.Visibility in [.idle, .hidden, .transcribing, .done] {
            viewModel.apply(visibility: state)
            XCTAssertFalse(viewModel.isAudioActive, "isAudioActive must be false for \(state)")
        }
    }

    // MARK: - Pill style

    func testHoverStatePublishesOnlyWhenItChanges() {
        let viewModel = PillOverlayViewModel()
        var values: [Bool] = []
        let cancellable = viewModel.$isHovered.dropFirst().sink { values.append($0) }

        viewModel.setHovered(true)
        viewModel.setHovered(true)
        viewModel.setHovered(false)

        XCTAssertEqual(values, [true, false])
        _ = cancellable
    }

    func testNoneStyleNeverShowsThePillAndOtherStylesRestoreIt() {
        let viewModel = PillOverlayViewModel()
        viewModel.apply(visibility: .recording)

        viewModel.setPillStyle(.none)
        XCTAssertEqual(viewModel.visibility, .hidden)

        viewModel.apply(visibility: .transcribing)
        XCTAssertEqual(viewModel.visibility, .hidden, "session updates stay hidden under None")

        viewModel.setPillStyle(.classic)
        XCTAssertEqual(viewModel.visibility, .transcribing)
    }

    func testMiniStyleShrinksEveryStateProportionally() {
        let full = PillOverlayView.size(for: .recording, style: .classic)
        let mini = PillOverlayView.size(for: .recording, style: .mini)

        XCTAssertEqual(full, PillOverlayView.size(for: .recording))
        XCTAssertLessThan(mini.width, full.width)
        XCTAssertEqual(mini.width / full.width, mini.height / full.height, accuracy: 0.001)
    }

    // MARK: - Cancel Card

    func testResumeFiresCallbackWhileCancelCardShown() {
        let viewModel = PillOverlayViewModel()
        var resumes = 0
        viewModel.onResumeCancelledRecording = { resumes += 1 }
        viewModel.apply(visibility: .cancelled)

        viewModel.resumeCancelledRecording()

        XCTAssertEqual(resumes, 1)
    }

    func testResumeIsNoopWhenNotCancelled() {
        let viewModel = PillOverlayViewModel()
        var resumes = 0
        viewModel.onResumeCancelledRecording = { resumes += 1 }

        viewModel.resumeCancelledRecording()

        XCTAssertEqual(resumes, 0)
        XCTAssertEqual(viewModel.visibility, .idle)
    }

    func testHoldToRecordIsStickyAgainstIncomingRecordingVisibility() {
        // #071: sticky-hold-to-record was removed. The store now derives
        // `.holdToRecord` from `SessionState.holdRecording` directly
        // (not from a side-channel push), and hold-release drives the
        // session through `.transcribing`/`.idle` via the normal
        // state-mapping — no need to block incoming `.recording` at
        // the view-model layer. Transitions are transparent.
        let viewModel = PillOverlayViewModel()
        viewModel.apply(visibility: .holdToRecord)
        XCTAssertEqual(viewModel.visibility, .holdToRecord)

        viewModel.apply(visibility: .recording)
        XCTAssertEqual(
            viewModel.visibility,
            .recording,
            "post-#071: no sticky-hold block — transitions are transparent"
        )

        viewModel.apply(visibility: .holdToRecord)
        viewModel.apply(visibility: .transcribing)
        XCTAssertEqual(viewModel.visibility, .transcribing)
    }

}
