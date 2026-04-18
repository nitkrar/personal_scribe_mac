import Combine
import XCTest
import SeshatCore
@testable import SeshatAppKit

@MainActor
final class PillOverlayViewModelTests: XCTestCase {
    func testInitialVisibilityIsHidden() {
        let viewModel = PillOverlayViewModel()

        XCTAssertEqual(viewModel.visibility, .hidden)
    }

    func testIdleMapsToHidden() {
        let viewModel = PillOverlayViewModel()

        viewModel.apply(sessionState: .idle)

        XCTAssertEqual(viewModel.visibility, .hidden)
    }

    func testRecordingMapsToRecording() {
        let viewModel = PillOverlayViewModel()

        viewModel.apply(sessionState: .recording)

        XCTAssertEqual(viewModel.visibility, .recording)
    }

    func testTranscribingMapsToTranscribing() {
        let viewModel = PillOverlayViewModel()

        viewModel.apply(sessionState: .transcribing)

        XCTAssertEqual(viewModel.visibility, .transcribing)
    }

    func testErrorMapsToHidden() {
        let viewModel = PillOverlayViewModel()

        viewModel.apply(sessionState: .error(.audioEngineFailure))

        XCTAssertEqual(viewModel.visibility, .hidden)
    }

    func testTransitionSequenceIdleRecordingTranscribingIdle() async {
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

        viewModel.apply(sessionState: .idle)
        viewModel.apply(sessionState: .recording)
        viewModel.apply(sessionState: .transcribing)
        viewModel.apply(sessionState: .idle)

        await fulfillment(of: [expectation], timeout: 1.0)
        withExtendedLifetime(cancellable) {}

        XCTAssertEqual(viewModel.visibility, .hidden)
        XCTAssertEqual(emitted, [.hidden, .recording, .transcribing, .hidden])
    }
}
