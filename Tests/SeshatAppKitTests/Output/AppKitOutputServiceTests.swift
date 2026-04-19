import XCTest
import SeshatCore
@testable import SeshatAppKit

@MainActor
final class AppKitOutputServiceTests: XCTestCase {
    func testPasteDelegatesToPasteOutputService() async throws {
        let pasteService = RecordingPasteOutputService()
        let copyService = RecordingCopyOutputService()
        let service = AppKitOutputService(
            pasteService: pasteService,
            copyService: copyService,
            streamingHandleFactory: { RecordingOutputStreamHandle() }
        )

        try await service.paste(text: "layer 5 paste")

        XCTAssertEqual(pasteService.receivedTexts, ["layer 5 paste"])
        XCTAssertTrue(copyService.receivedTexts.isEmpty)
    }

    func testCopyDelegatesToCopyOutputService() async throws {
        let pasteService = RecordingPasteOutputService()
        let copyService = RecordingCopyOutputService()
        let service = AppKitOutputService(
            pasteService: pasteService,
            copyService: copyService,
            streamingHandleFactory: { RecordingOutputStreamHandle() }
        )

        try await service.copy(text: "layer 5 copy")

        XCTAssertEqual(copyService.receivedTexts, ["layer 5 copy"])
        XCTAssertTrue(pasteService.receivedTexts.isEmpty)
    }

    func testBeginStreamReturnsFactoryHandle() {
        let pasteService = RecordingPasteOutputService()
        let copyService = RecordingCopyOutputService()
        let handle = RecordingOutputStreamHandle()
        let service = AppKitOutputService(
            pasteService: pasteService,
            copyService: copyService,
            streamingHandleFactory: { handle }
        )

        let stream = service.beginStream()
        stream.append("chunk")
        stream.finalize()

        XCTAssertEqual(handle.appendedChunks, ["chunk"])
        XCTAssertEqual(handle.finalizeCount, 1)
    }
}

@MainActor
private final class RecordingPasteOutputService: PasteOutputServing, @unchecked Sendable {
    private(set) var receivedTexts: [String] = []

    func paste(text: String) async throws {
        receivedTexts.append(text)
    }
}

@MainActor
private final class RecordingCopyOutputService: CopyOutputServing, @unchecked Sendable {
    private(set) var receivedTexts: [String] = []

    func copy(text: String) async throws {
        receivedTexts.append(text)
    }
}

@MainActor
private final class RecordingOutputStreamHandle: OutputStreamHandle, @unchecked Sendable {
    private(set) var appendedChunks: [String] = []
    private(set) var finalizeCount = 0

    func append(_ chunk: String) {
        appendedChunks.append(chunk)
    }

    func finalize() {
        finalizeCount += 1
    }
}
