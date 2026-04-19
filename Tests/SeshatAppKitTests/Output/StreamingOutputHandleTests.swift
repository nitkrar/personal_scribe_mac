import XCTest
import SeshatCore
@testable import SeshatAppKit

@MainActor
final class StreamingOutputHandleTests: XCTestCase {
    func testAppendConsumesPartialChunksInOrderUntilFinalize() {
        var appendedChunks: [String] = []
        var finalizedPayloads: [[String]] = []
        let handle = StreamingOutputHandle(
            transportSelection: .resolved(.typeEvents),
            onAppendChunk: { appendedChunks.append($0) },
            onFinalizeChunks: { finalizedPayloads.append($0) }
        )

        handle.append("hel")
        handle.append("lo")
        handle.finalize()
        handle.append(" ignored")
        handle.finalize()

        XCTAssertEqual(appendedChunks, ["hel", "lo"])
        XCTAssertEqual(handle.appendedChunks, ["hel", "lo"])
        XCTAssertEqual(handle.finalizedChunks, ["hel", "lo"])
        XCTAssertEqual(finalizedPayloads, [["hel", "lo"]])
        XCTAssertEqual(handle.finalizedDelivery, .typeEvents)
        XCTAssertNil(handle.finalizationError)
        XCTAssertTrue(handle.isFinalized)
    }

    func testLiveStreamPathRequiresBacklogDecisionBeforeConsumerAdoption() {
        let handle = StreamingOutputHandle.live()

        handle.append("partial ")
        handle.append("text")
        handle.finalize()

        XCTAssertEqual(handle.appendedChunks, ["partial ", "text"])
        XCTAssertEqual(handle.finalizedChunks, ["partial ", "text"])
        XCTAssertNil(handle.finalizedDelivery)
        XCTAssertEqual(handle.finalizationError, .streamingTransportDecisionRequired)
    }
}
