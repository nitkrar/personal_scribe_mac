import XCTest
@testable import SeshatCore

@MainActor
final class OutputContractsTests: XCTestCase {
    func testOutputModeHasPasteCopyBoth() {
        XCTAssertEqual(OutputMode.allCases, [.paste, .copy, .both])
    }

    func testOutputTargetCasesStayLocked() {
        XCTAssertEqual(OutputTarget.allCases, [.frontmostApp, .clipboardOnly, .selfFrontmost])
    }

    func testOutputDeliveryCasesStayLocked() {
        XCTAssertEqual(OutputDelivery.allCases, [.paste, .typeEvents, .clipboardOnly])
    }

    func testOutputErrorCasesStayLocked() {
        let errors: [OutputError] = [
            .clipboardWriteFailed,
            .clipboardOnlyFallback,
            .streamingTransportDecisionRequired,
            .copyUnavailable,
        ]

        XCTAssertEqual(
            errors,
            [
                .clipboardWriteFailed,
                .clipboardOnlyFallback,
                .streamingTransportDecisionRequired,
                .copyUnavailable,
            ]
        )
    }

    func testOutputServiceExposesPasteCopyAndBeginStreamOnly() async throws {
        let service = RecordingOutputService()

        try await service.paste(text: "pasted text")
        try await service.copy(text: "copied text")
        let handle = service.beginStream()
        handle.append("chunk")
        handle.finalize()

        XCTAssertEqual(service.pastedTexts, ["pasted text"])
        XCTAssertEqual(service.copiedTexts, ["copied text"])
        XCTAssertEqual(service.handle.appendedChunks, ["chunk"])
        XCTAssertEqual(service.handle.finalizeCount, 1)
    }

    func testOutputStreamHandleSupportsAppendAndFinalize() {
        let handle = RecordingOutputStreamHandle()

        handle.append("hello")
        handle.append(" world")
        handle.finalize()

        XCTAssertEqual(handle.appendedChunks, ["hello", " world"])
        XCTAssertEqual(handle.finalizeCount, 1)
    }
}

@MainActor
private final class RecordingOutputService: OutputService, @unchecked Sendable {
    private(set) var pastedTexts: [String] = []
    private(set) var copiedTexts: [String] = []
    let handle = RecordingOutputStreamHandle()

    func paste(text: String) async throws {
        pastedTexts.append(text)
    }

    func copy(text: String) async throws {
        copiedTexts.append(text)
    }

    func beginStream() -> any OutputStreamHandle {
        handle
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
