import AppKit
import XCTest
import SeshatCore
@testable import SeshatAppKit

@MainActor
final class PasteInjectorTests: XCTestCase {
    private let suiteName = "SeshatTestsPasteInjector"

    private func makePasteboard() -> NSPasteboard {
        NSPasteboard(name: NSPasteboard.Name(rawValue: "seshat.test.\(UUID().uuidString)"))
    }

    private func isolatedDefaults() -> UserDefaults {
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    func testPromptsAccessibilityWhenNotTrustedAndLeavesTranscriptOnClipboard() {
        let pasteboard = makePasteboard()
        var promptCount = 0
        var shortcutPostCount = 0
        let injector = PasteInjector.live(
            logger: SeshatLogger(category: SeshatLogCategory.ui),
            pasteboard: pasteboard,
            restoreDelay: 0.01,
            scheduleRestore: { _, _ in },
            isAccessibilityTrusted: { false },
            requestAccessibilityPrompt: { promptCount += 1 },
            pasteShortcutPoster: { _ in
                shortcutPostCount += 1
                return true
            }
        )

        injector.paste("hello world")

        XCTAssertEqual(promptCount, 1)
        XCTAssertEqual(shortcutPostCount, 0)
        XCTAssertEqual(pasteboard.string(forType: .string), "hello world")
    }

    func testDoesNotPromptWhenAlreadyTrusted() {
        let pasteboard = makePasteboard()
        var promptCount = 0
        var shortcutPostCount = 0
        let injector = PasteInjector.live(
            logger: SeshatLogger(category: SeshatLogCategory.ui),
            pasteboard: pasteboard,
            restoreDelay: 0.01,
            scheduleRestore: { _, _ in },
            isAccessibilityTrusted: { true },
            requestAccessibilityPrompt: { promptCount += 1 },
            pasteShortcutPoster: { _ in
                shortcutPostCount += 1
                return true
            }
        )

        injector.paste("already trusted")

        XCTAssertEqual(promptCount, 0)
        XCTAssertEqual(shortcutPostCount, 1)
    }

    func testPasteReturnsClipboardOnlyWhenModeIsClipboardOnly() {
        let defaults = isolatedDefaults()
        SeshatPasteMode.clipboardOnly.persist(to: defaults)
        let pasteboard = makePasteboard()
        var shortcutPostCount = 0
        let injector = PasteInjector(
            logger: SeshatLogger(category: SeshatLogCategory.ui),
            pasteboard: pasteboard,
            defaults: defaults,
            frontmostAppProvider: FakeFrontmostAppProvider(
                frontmostApplicationBundleIdentifier: "com.apple.TextEdit"
            ),
            restoreDelay: 0.01,
            scheduleRestore: { _, _ in },
            isAccessibilityTrusted: { true },
            requestAccessibilityPrompt: {},
            pasteShortcutPoster: { _ in
                shortcutPostCount += 1
                return true
            }
        )

        let route = injector.paste("clipboard only")

        XCTAssertEqual(route, .clipboardOnly(reason: .clipboardOnlyMode))
        XCTAssertEqual(shortcutPostCount, 0)
        XCTAssertEqual(pasteboard.string(forType: .string), "clipboard only")
    }

    func testPasteReturnsClipboardOnlyWhenFrontmostAppIsSeshat() {
        let defaults = isolatedDefaults()
        SeshatPasteMode.pasteAtCursor.persist(to: defaults)
        let pasteboard = makePasteboard()
        var shortcutPostCount = 0
        let injector = PasteInjector(
            logger: SeshatLogger(category: SeshatLogCategory.ui),
            pasteboard: pasteboard,
            defaults: defaults,
            frontmostAppProvider: FakeFrontmostAppProvider(
                frontmostApplicationBundleIdentifier: "com.nitkrar.seshat"
            ),
            restoreDelay: 0.01,
            scheduleRestore: { _, _ in },
            isAccessibilityTrusted: { true },
            requestAccessibilityPrompt: {},
            pasteShortcutPoster: { _ in
                shortcutPostCount += 1
                return true
            }
        )

        let route = injector.paste("self frontmost")

        XCTAssertEqual(route, .clipboardOnly(reason: .frontmostAppIsSeshat))
        XCTAssertEqual(shortcutPostCount, 0)
        XCTAssertEqual(pasteboard.string(forType: .string), "self frontmost")
    }

    func testEmptyTranscriptIsNoop() {
        let pasteboard = makePasteboard()
        pasteboard.clearContents()
        _ = pasteboard.setString("prior", forType: .string)
        var promptCount = 0
        var shortcutPostCount = 0
        let injector = PasteInjector.live(
            logger: SeshatLogger(category: SeshatLogCategory.ui),
            pasteboard: pasteboard,
            restoreDelay: 0.01,
            scheduleRestore: { _, _ in },
            isAccessibilityTrusted: { false },
            requestAccessibilityPrompt: { promptCount += 1 },
            pasteShortcutPoster: { _ in
                shortcutPostCount += 1
                return true
            }
        )

        injector.paste("")

        XCTAssertEqual(promptCount, 0)
        XCTAssertEqual(shortcutPostCount, 0)
        XCTAssertEqual(pasteboard.string(forType: .string), "prior")
    }

    func testSchedulesClipboardRestoreWhenTrusted() {
        let pasteboard = makePasteboard()
        var scheduledAction: (() -> Void)?
        var shortcutPostCount = 0
        let injector = PasteInjector.live(
            logger: SeshatLogger(category: SeshatLogCategory.ui),
            pasteboard: pasteboard,
            restoreDelay: 0.01,
            scheduleRestore: { _, action in
                scheduledAction = action
            },
            isAccessibilityTrusted: { true },
            requestAccessibilityPrompt: {},
            pasteShortcutPoster: { _ in
                shortcutPostCount += 1
                return true
            }
        )

        pasteboard.clearContents()
        _ = pasteboard.setString("original", forType: .string)

        injector.paste("transcript")

        XCTAssertEqual(shortcutPostCount, 1)
        XCTAssertEqual(pasteboard.string(forType: .string), "transcript")
        XCTAssertNotNil(scheduledAction)
        scheduledAction?()
        XCTAssertEqual(pasteboard.string(forType: .string), "original")
    }
}

@MainActor
private struct FakeFrontmostAppProvider: FrontmostAppProviding {
    let frontmostApplicationBundleIdentifier: String?
}
