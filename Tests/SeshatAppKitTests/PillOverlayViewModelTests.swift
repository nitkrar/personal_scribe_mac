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

    func testIdleSessionMapsToIdlePill() {
        let viewModel = PillOverlayViewModel()

        viewModel.apply(sessionState: .idle, preparationProgress: nil)

        XCTAssertEqual(viewModel.visibility, .idle)
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

    func testErrorMapsToHidden() {
        let viewModel = PillOverlayViewModel()

        viewModel.apply(sessionState: .error(.audioEngineFailure), preparationProgress: nil)

        XCTAssertEqual(viewModel.visibility, .hidden)
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

    func testFinishedDownloadRestoresIdlePill() {
        let viewModel = PillOverlayViewModel()
        let progress = ModelDownloadProgress(
            phase: .finished,
            fractionCompleted: 1.0,
            receivedBytes: 100,
            expectedBytes: 100
        )

        viewModel.apply(sessionState: .idle, preparationProgress: progress)

        XCTAssertEqual(viewModel.visibility, .idle)
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

    func testTransitionSequenceIdleRecordingTranscribingIdleError() async {
        let viewModel = PillOverlayViewModel()
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

        XCTAssertEqual(viewModel.visibility, .hidden)
        XCTAssertEqual(emitted, [.recording, .transcribing, .idle, .hidden])
    }
}
