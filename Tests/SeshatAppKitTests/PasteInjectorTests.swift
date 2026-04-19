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
        let defaults = isolatedDefaults()
        var promptCount = 0
        var shortcutPostCount = 0
        let injector = PasteInjector(
            logger: SeshatLogger(category: SeshatLogCategory.ui),
            pasteboard: pasteboard,
            defaults: defaults,
            frontmostAppProvider: FakeFrontmostAppProvider(
                frontmostApplicationBundleIdentifier: "com.apple.TextEdit"
            ),
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
        let defaults = isolatedDefaults()
        var promptCount = 0
        var shortcutPostCount = 0
        let injector = PasteInjector(
            logger: SeshatLogger(category: SeshatLogCategory.ui),
            pasteboard: pasteboard,
            defaults: defaults,
            frontmostAppProvider: FakeFrontmostAppProvider(
                frontmostApplicationBundleIdentifier: "com.apple.TextEdit"
            ),
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
        let defaults = isolatedDefaults()
        pasteboard.clearContents()
        _ = pasteboard.setString("prior", forType: .string)
        var promptCount = 0
        var shortcutPostCount = 0
        let injector = PasteInjector(
            logger: SeshatLogger(category: SeshatLogCategory.ui),
            pasteboard: pasteboard,
            defaults: defaults,
            frontmostAppProvider: FakeFrontmostAppProvider(
                frontmostApplicationBundleIdentifier: "com.apple.TextEdit"
            ),
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

    func testPasteReadsRestoreDelayPreferencePerCall() {
        let pasteboard = makePasteboard()
        let defaults = isolatedDefaults()
        var scheduledRestores: [(delay: TimeInterval, action: @MainActor () -> Void)] = []
        let injector = PasteInjector(
            logger: SeshatLogger(category: SeshatLogCategory.ui),
            pasteboard: pasteboard,
            defaults: defaults,
            frontmostAppProvider: FakeFrontmostAppProvider(
                frontmostApplicationBundleIdentifier: "com.apple.TextEdit"
            ),
            scheduleRestore: { delay, action in
                scheduledRestores.append((delay: delay, action: action))
            },
            isAccessibilityTrusted: { true },
            requestAccessibilityPrompt: {},
            pasteShortcutPoster: { _ in true }
        )

        pasteboard.clearContents()
        _ = pasteboard.setString("original one", forType: .string)
        PasteRestoreDelay.persist(to: defaults, PasteRestoreDelay(seconds: 0.2))

        injector.paste("transcript one")

        XCTAssertEqual(scheduledRestores.count, 1)
        XCTAssertEqual(scheduledRestores[0].delay, 0.2, accuracy: 0.0001)
        XCTAssertEqual(pasteboard.string(forType: .string), "transcript one")
        scheduledRestores[0].action()
        XCTAssertEqual(pasteboard.string(forType: .string), "original one")

        pasteboard.clearContents()
        _ = pasteboard.setString("original two", forType: .string)
        PasteRestoreDelay.persist(to: defaults, PasteRestoreDelay(seconds: 1.4))

        injector.paste("transcript two")

        XCTAssertEqual(scheduledRestores.count, 2)
        XCTAssertEqual(scheduledRestores[1].delay, 1.4, accuracy: 0.0001)
        XCTAssertEqual(pasteboard.string(forType: .string), "transcript two")
        scheduledRestores[1].action()
        XCTAssertEqual(pasteboard.string(forType: .string), "original two")
    }
}

@MainActor
private struct FakeFrontmostAppProvider: FrontmostAppProviding {
    let frontmostApplicationBundleIdentifier: String?
}
