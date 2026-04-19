import AppKit
import XCTest
import SeshatCore
@testable import SeshatAppKit

@MainActor
final class CopyOutputServiceTests: XCTestCase {
    private func makePasteboard() -> NSPasteboard {
        NSPasteboard(name: NSPasteboard.Name(rawValue: "seshat.copy.output.test.\(UUID().uuidString)"))
    }

    func testCopyWritesPlainStringToPasteboard() async throws {
        let pasteboard = makePasteboard()
        let service = CopyOutputService(
            logger: SeshatLogger(category: SeshatLogCategory.ui),
            pasteboard: pasteboard
        )

        try await service.copy(text: "copied transcript")

        XCTAssertEqual(pasteboard.string(forType: .string), "copied transcript")
    }

    func testCopyLeavesPasteboardUntouchedForEmptyInput() async throws {
        let pasteboard = makePasteboard()
        pasteboard.clearContents()
        _ = pasteboard.setString("existing value", forType: .string)
        let service = CopyOutputService(
            logger: SeshatLogger(category: SeshatLogCategory.ui),
            pasteboard: pasteboard
        )

        try await service.copy(text: "")

        XCTAssertEqual(pasteboard.string(forType: .string), "existing value")
    }
}
