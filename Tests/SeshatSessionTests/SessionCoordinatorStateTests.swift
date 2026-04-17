import XCTest
import SeshatCore
import SeshatTestSupport
@testable import SeshatSession

final class SessionCoordinatorStateTests: XCTestCase {
    func testStateStreamDeliversInitialStateImmediately() async {
        let coordinator = SessionCoordinator(
            capture: FakeAudioCapturing(),
            transcriber: FakeTranscriber(
                result: .init(
                    text: "",
                    audioDuration: .zero,
                    processingDuration: .zero
                )
            ),
            logger: SeshatLogger(category: SeshatLogCategory.session)
        )

        let stream = await coordinator.stateStream()
        var iterator = stream.makeAsyncIterator()
        let initialState = await iterator.next()
        let lastResult = await coordinator.lastResult()

        XCTAssertEqual(initialState, .idle)
        XCTAssertNil(lastResult)
    }
}
