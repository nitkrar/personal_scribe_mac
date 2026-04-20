import XCTest
@testable import PersonalScribeCore

@MainActor
final class OutputContractsTests: XCTestCase {
    func testOutputModeHasBatchAndStreaming() {
        XCTAssertEqual(OutputMode.allCases, [.batch, .streaming])
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
        ]

        XCTAssertEqual(
            errors,
            [
                .clipboardWriteFailed,
            ]
        )
    }

    func testOutputResultRepresentsDeliveredFailedAndIgnoredInputOutcomes() {
        XCTAssertEqual(
            OutputResult.delivered(target: .frontmostApp, delivery: .paste),
            .delivered(target: .frontmostApp, delivery: .paste)
        )
        XCTAssertEqual(OutputResult.ignoredEmptyInput, .ignoredEmptyInput)
        XCTAssertEqual(OutputResult.failed(.clipboardWriteFailed), .failed(.clipboardWriteFailed))
    }

    func testOutputServiceExposesDeliverBatchOnly() async {
        let service = RecordingOutputService(
            result: .delivered(target: .clipboardOnly, delivery: .clipboardOnly)
        )

        let result = await service.deliverBatch(text: "batched text")

        XCTAssertEqual(service.receivedTexts, ["batched text"])
        XCTAssertEqual(result, .delivered(target: .clipboardOnly, delivery: .clipboardOnly))
    }
}

@MainActor
private final class RecordingOutputService: OutputService, @unchecked Sendable {
    private(set) var receivedTexts: [String] = []
    private let result: OutputResult

    init(result: OutputResult) {
        self.result = result
    }

    func deliverBatch(text: String) async -> OutputResult {
        receivedTexts.append(text)
        return result
    }
}
