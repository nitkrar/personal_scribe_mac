import Combine
import XCTest
import SeshatCore
@testable import SeshatAppKit

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

        viewModel.apply(sessionState: .recording, preparationProgress: nil)

        XCTAssertEqual(viewModel.visibility, .recording)
    }

    func testTranscribingMapsToTranscribing() {
        let viewModel = PillOverlayViewModel()

        viewModel.apply(sessionState: .transcribing, preparationProgress: nil)

        XCTAssertEqual(viewModel.visibility, .transcribing)
    }

    func testErrorSessionStateSurfacesAsVisibleErrorPillWithMessage() {
        // Previously .error mapped to .hidden, which made transcription
        // failures look like the pill had crashed. The fix surfaces the
        // error as a brief visible `.error(message:)` pill. Here we
        // verify for two representative SeshatError cases.
        let vmA = PillOverlayViewModel()
        vmA.apply(sessionState: .error(.audioEngineFailure), preparationProgress: nil)
        XCTAssertEqual(
            vmA.visibility,
            .error(message: PillOverlayViewModel.pillMessage(for: .audioEngineFailure))
        )

        let vmB = PillOverlayViewModel()
        vmB.apply(sessionState: .error(.recordingTooShort), preparationProgress: nil)
        XCTAssertEqual(
            vmB.visibility,
            .error(message: PillOverlayViewModel.pillMessage(for: .recordingTooShort))
        )
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

        viewModel.apply(sessionState: .recording, preparationProgress: progress)

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

        viewModel.apply(sessionState: .recording, preparationProgress: nil)

        XCTAssertEqual(viewModel.visibility, .recording)
    }

    func testHiddenModeHidesIdleButRecordingOverridesHidden() {
        // Sprint 2 redesign (2026-04-18) reversed the prior rule.
        // Claude's pill spec requires the stop affordance to stay
        // reachable during `.recording` regardless of the user's
        // visibility preference. The menu bar still satisfies the
        // "at-least-one-surface-visible" invariant in Phase 2.
        let viewModel = PillOverlayViewModel(visibilityMode: .hidden)

        viewModel.apply(sessionState: .idle, preparationProgress: nil)
        XCTAssertEqual(viewModel.visibility, .hidden)

        viewModel.apply(sessionState: .recording, preparationProgress: nil)
        XCTAssertEqual(viewModel.visibility, .recording,
                       "Recording must override hidden mode (stop affordance)")

        viewModel.apply(sessionState: .transcribing, preparationProgress: nil)
        XCTAssertEqual(viewModel.visibility, .transcribing,
                       "Transcribing continues showing the pill after recording override until we return to idle")

        let progress = ModelDownloadProgress(
            phase: .downloading,
            fractionCompleted: 0.5,
            receivedBytes: 50,
            expectedBytes: 100
        )
        // Transcribing → idle fires the `.done` confirmation (prior
        // state was transcribing). Consume that first before checking
        // the idle-hidden behaviour.
        viewModel.apply(sessionState: .idle, preparationProgress: nil)
        XCTAssertEqual(viewModel.visibility, .done)

        // The AppStore now derives visibility centrally, and hidden mode
        // still surfaces active download progress even when the session is idle.
        viewModel.apply(sessionState: .idle, preparationProgress: progress)
        XCTAssertEqual(viewModel.visibility, .downloading(fractionCompleted: 0.5))
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

        viewModel.setVisibilityMode(.hidden)
        XCTAssertEqual(viewModel.visibilityMode, .hidden)
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
        // Error sessions render a visible error pill (fix per 16b5055 —
        // prior behaviour routed errors through `.hidden`, which looked
        // like the pill had crashed). The pill falls through to idle
        // after `errorDisplayDuration`; this test stops before that.
        //   recording → transcribing → done → error(message)
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

        viewModel.apply(sessionState: .recording, preparationProgress: nil)
        viewModel.apply(sessionState: .transcribing, preparationProgress: nil)
        viewModel.apply(sessionState: .idle, preparationProgress: nil)
        viewModel.apply(sessionState: .error(.audioEngineFailure), preparationProgress: nil)

        await fulfillment(of: [expectation], timeout: 1.0)
        withExtendedLifetime(cancellable) {}

        let expectedErrorMessage = PillOverlayViewModel.pillMessage(for: .audioEngineFailure)
        XCTAssertEqual(viewModel.visibility, .error(message: expectedErrorMessage))
        XCTAssertEqual(
            emitted,
            [.recording, .transcribing, .done, .error(message: expectedErrorMessage)]
        )
    }

    func testTranscribingToIdleShowsDoneConfirmation() {
        // Core semantics of the `.done` transient state: when the
        // session transitions transcribing → idle (success path),
        // the view model emits `.done` immediately so the pill can
        // show a checkmark. The done task then falls through to the
        // mode's normal idle after `doneConfirmationDuration`.
        let viewModel = PillOverlayViewModel(visibilityMode: .autoShow)

        viewModel.apply(sessionState: .recording, preparationProgress: nil)
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

        viewModel.apply(sessionState: .recording, preparationProgress: nil)
        XCTAssertEqual(viewModel.visibility, .recording)
    }
}
