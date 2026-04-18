import AppKit
import XCTest
import SeshatCore
@testable import SeshatAppKit

@MainActor
final class PasteInjectorTests: XCTestCase {
    private func makePasteboard() -> NSPasteboard {
        NSPasteboard(name: NSPasteboard.Name(rawValue: "seshat.test.\(UUID().uuidString)"))
    }

    func testPromptsAccessibilityWhenNotTrustedAndLeavesTranscriptOnClipboard() {
        let pasteboard = makePasteboard()
        var promptCount = 0
        let injector = PasteInjector(
            logger: SeshatLogger(category: SeshatLogCategory.ui),
            pasteboard: pasteboard,
            restoreDelay: 0.01,
            scheduleRestore: { _, _ in },
            isAccessibilityTrusted: { false },
            requestAccessibilityPrompt: { promptCount += 1 }
        )

        injector.paste("hello world")

        XCTAssertEqual(promptCount, 1)
        XCTAssertEqual(pasteboard.string(forType: .string), "hello world")
    }

    func testDoesNotPromptWhenAlreadyTrusted() {
        let pasteboard = makePasteboard()
        var promptCount = 0
        let injector = PasteInjector(
            logger: SeshatLogger(category: SeshatLogCategory.ui),
            pasteboard: pasteboard,
            restoreDelay: 0.01,
            scheduleRestore: { _, _ in },
            isAccessibilityTrusted: { true },
            requestAccessibilityPrompt: { promptCount += 1 }
        )

        injector.paste("already trusted")

        XCTAssertEqual(promptCount, 0)
    }

    func testEmptyTranscriptIsNoop() {
        let pasteboard = makePasteboard()
        pasteboard.clearContents()
        _ = pasteboard.setString("prior", forType: .string)
        var promptCount = 0
        let injector = PasteInjector(
            logger: SeshatLogger(category: SeshatLogCategory.ui),
            pasteboard: pasteboard,
            restoreDelay: 0.01,
            scheduleRestore: { _, _ in },
            isAccessibilityTrusted: { false },
            requestAccessibilityPrompt: { promptCount += 1 }
        )

        injector.paste("")

        XCTAssertEqual(promptCount, 0)
        XCTAssertEqual(pasteboard.string(forType: .string), "prior")
    }

    func testSchedulesClipboardRestoreWhenTrusted() {
        let pasteboard = makePasteboard()
        var scheduledAction: (() -> Void)?
        let injector = PasteInjector(
            logger: SeshatLogger(category: SeshatLogCategory.ui),
            pasteboard: pasteboard,
            restoreDelay: 0.01,
            scheduleRestore: { _, action in
                scheduledAction = action
            },
            isAccessibilityTrusted: { true },
            requestAccessibilityPrompt: {}
        )

        pasteboard.clearContents()
        _ = pasteboard.setString("original", forType: .string)

        injector.paste("transcript")

        XCTAssertEqual(pasteboard.string(forType: .string), "transcript")
        XCTAssertNotNil(scheduledAction)
        scheduledAction?()
        XCTAssertEqual(pasteboard.string(forType: .string), "original")
    }
}
