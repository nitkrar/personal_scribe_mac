import AppKit
import Foundation
import SeshatCore

@MainActor
protocol CopyOutputServing: Sendable {
    func copy(text: String) async throws
}

@MainActor
final class CopyOutputService: CopyOutputServing, @unchecked Sendable {
    private let logger: SeshatLogger
    private let pasteboard: NSPasteboard

    init(
        logger: SeshatLogger = SeshatLogger(category: SeshatLogCategory.ui),
        pasteboard: NSPasteboard = .general
    ) {
        self.logger = logger
        self.pasteboard = pasteboard
    }

    func copy(text: String) async throws {
        guard !text.isEmpty else { return }

        pasteboard.clearContents()
        guard pasteboard.setString(text, forType: .string) else {
            logger.info("CopyOutputService: failed to write transcript to pasteboard")
            throw OutputError.clipboardWriteFailed
        }
    }
}
