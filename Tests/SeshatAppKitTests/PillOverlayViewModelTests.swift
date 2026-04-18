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

    func testIdleMapsToIdle() {
        let viewModel = PillOverlayViewModel()

        viewModel.apply(sessionState: .idle, downloadProgress: nil)

        XCTAssertEqual(viewModel.visibility, .idle)
    }

    func testRecordingMapsToRecording() {
        let viewModel = PillOverlayViewModel()

        viewModel.apply(sessionState: .recording, downloadProgress: nil)

        XCTAssertEqual(viewModel.visibility, .recording)
    }

    func testTranscribingMapsToTranscribing() {
        let viewModel = PillOverlayViewModel()

        viewModel.apply(sessionState: .transcribing, downloadProgress: nil)

        XCTAssertEqual(viewModel.visibility, .transcribing)
    }

    func testErrorMapsToHidden() {
        let viewModel = PillOverlayViewModel()

        viewModel.apply(sessionState: .error(.audioEngineFailure), downloadProgress: nil)

        XCTAssertEqual(viewModel.visibility, .hidden)
    }

    func testDownloadingProgressOverridesSessionState() {
        let viewModel = PillOverlayViewModel()
        let progress = ModelDownloadProgress(
            phase: .downloading,
            fractionCompleted: 0.42,
            receivedBytes: 42,
            expectedBytes: 100
        )

        viewModel.apply(sessionState: .transcribing, downloadProgress: progress)

        XCTAssertEqual(viewModel.visibility, .downloading(fractionCompleted: 0.42))
    }

    func testFinishedProgressDoesNotHijackVisibility() {
        let viewModel = PillOverlayViewModel()
        let progress = ModelDownloadProgress(
            phase: .finished,
            fractionCompleted: 1.0,
            receivedBytes: 100,
            expectedBytes: 100
        )

        viewModel.apply(sessionState: .recording, downloadProgress: progress)

        XCTAssertEqual(viewModel.visibility, .recording)
    }

    func testTransitionSequenceRecordingTranscribingIdleError() async {
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

        viewModel.apply(sessionState: .recording, downloadProgress: nil)
        viewModel.apply(sessionState: .transcribing, downloadProgress: nil)
        viewModel.apply(sessionState: .idle, downloadProgress: nil)
        viewModel.apply(sessionState: .error(.audioEngineFailure), downloadProgress: nil)

        await fulfillment(of: [expectation], timeout: 1.0)
        withExtendedLifetime(cancellable) {}

        XCTAssertEqual(viewModel.visibility, .hidden)
        XCTAssertEqual(emitted, [.recording, .transcribing, .idle, .hidden])
    }
}
