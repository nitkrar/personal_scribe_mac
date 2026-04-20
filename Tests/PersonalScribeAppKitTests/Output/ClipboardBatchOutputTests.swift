import AppKit
import XCTest
import PersonalScribeCore
@testable import PersonalScribeAppKit

@MainActor
final class ClipboardBatchOutputTests: XCTestCase {
    private let suiteName = "PersonalScribeTestsClipboardBatchOutput"

    private func makePasteboard() -> NSPasteboard {
        NSPasteboard(name: NSPasteboard.Name(rawValue: "personal_scribe.test.\(UUID().uuidString)"))
    }

    private func isolatedDefaults() -> UserDefaults {
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    func testPromptsAccessibilityWhenNotTrustedAndLeavesTranscriptOnClipboard() async {
        let pasteboard = makePasteboard()
        let defaults = isolatedDefaults()
        var promptCount = 0
        var shortcutPostCount = 0
        let service = ClipboardBatchOutput(
            logger: PersonalScribeLogger(category: PersonalScribeLogCategory.ui),
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

        let result = await service.deliverBatch(text: "hello world")

        XCTAssertEqual(result, .delivered(target: .frontmostApp, delivery: .clipboardOnly))
        XCTAssertEqual(promptCount, 1)
        XCTAssertEqual(shortcutPostCount, 0)
        XCTAssertEqual(pasteboard.string(forType: .string), "hello world")
    }

    func testDeliversPasteWhenAccessibilityIsTrusted() async {
        let pasteboard = makePasteboard()
        let defaults = isolatedDefaults()
        var promptCount = 0
        var shortcutPostCount = 0
        let service = ClipboardBatchOutput(
            logger: PersonalScribeLogger(category: PersonalScribeLogCategory.ui),
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

        let result = await service.deliverBatch(text: "already trusted")

        XCTAssertEqual(result, .delivered(target: .frontmostApp, delivery: .paste))
        XCTAssertEqual(promptCount, 0)
        XCTAssertEqual(shortcutPostCount, 1)
    }

    func testDeliverBatchReturnsClipboardOnlyWhenModeIsClipboardOnly() async {
        let defaults = isolatedDefaults()
        PasteMode.preference(defaults: defaults).persist(.clipboardOnly)
        let pasteboard = makePasteboard()
        var shortcutPostCount = 0
        let service = ClipboardBatchOutput(
            logger: PersonalScribeLogger(category: PersonalScribeLogCategory.ui),
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

        let result = await service.deliverBatch(text: "clipboard only")

        XCTAssertEqual(result, .delivered(target: .clipboardOnly, delivery: .clipboardOnly))
        XCTAssertEqual(shortcutPostCount, 0)
        XCTAssertEqual(pasteboard.string(forType: .string), "clipboard only")
    }

    func testDeliverBatchReturnsClipboardOnlyWhenFrontmostAppIsPersonalScribe() async {
        let defaults = isolatedDefaults()
        PasteMode.preference(defaults: defaults).persist(.pasteAtCursor)
        let pasteboard = makePasteboard()
        var shortcutPostCount = 0
        let service = ClipboardBatchOutput(
            logger: PersonalScribeLogger(category: PersonalScribeLogCategory.ui),
            pasteboard: pasteboard,
            defaults: defaults,
            frontmostAppProvider: FakeFrontmostAppProvider(
                frontmostApplicationBundleIdentifier: "com.nitkrar.personal_scribe"
            ),
            scheduleRestore: { _, _ in },
            isAccessibilityTrusted: { true },
            requestAccessibilityPrompt: {},
            pasteShortcutPoster: { _ in
                shortcutPostCount += 1
                return true
            }
        )

        let result = await service.deliverBatch(text: "self frontmost")

        XCTAssertEqual(result, .delivered(target: .selfFrontmost, delivery: .clipboardOnly))
        XCTAssertEqual(shortcutPostCount, 0)
        XCTAssertEqual(pasteboard.string(forType: .string), "self frontmost")
    }

    func testEmptyTranscriptIsNoop() async {
        let pasteboard = makePasteboard()
        let defaults = isolatedDefaults()
        pasteboard.clearContents()
        _ = pasteboard.setString("prior", forType: .string)
        var promptCount = 0
        var shortcutPostCount = 0
        let service = ClipboardBatchOutput(
            logger: PersonalScribeLogger(category: PersonalScribeLogCategory.ui),
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

        let result = await service.deliverBatch(text: "")

        XCTAssertEqual(result, .ignoredEmptyInput)
        XCTAssertEqual(promptCount, 0)
        XCTAssertEqual(shortcutPostCount, 0)
        XCTAssertEqual(pasteboard.string(forType: .string), "prior")
    }

    func testDeliverBatchReadsRestoreDelayPreferencePerCall() async {
        let pasteboard = makePasteboard()
        let defaults = isolatedDefaults()
        var scheduledRestores: [(delay: TimeInterval, action: @MainActor () -> Void)] = []
        let service = ClipboardBatchOutput(
            logger: PersonalScribeLogger(category: PersonalScribeLogCategory.ui),
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
        PasteRestoreDelay.storedSeconds(defaults: defaults).persist(0.2)

        let firstResult = await service.deliverBatch(text: "transcript one")

        XCTAssertEqual(firstResult, .delivered(target: .frontmostApp, delivery: .paste))
        XCTAssertEqual(scheduledRestores.count, 1)
        XCTAssertEqual(scheduledRestores[0].delay, 0.2, accuracy: 0.0001)
        XCTAssertEqual(pasteboard.string(forType: .string), "transcript one")
        scheduledRestores[0].action()
        XCTAssertEqual(pasteboard.string(forType: .string), "original one")

        pasteboard.clearContents()
        _ = pasteboard.setString("original two", forType: .string)
        PasteRestoreDelay.storedSeconds(defaults: defaults).persist(1.4)

        let secondResult = await service.deliverBatch(text: "transcript two")

        XCTAssertEqual(secondResult, .delivered(target: .frontmostApp, delivery: .paste))
        XCTAssertEqual(scheduledRestores.count, 2)
        XCTAssertEqual(scheduledRestores[1].delay, 1.4, accuracy: 0.0001)
        XCTAssertEqual(pasteboard.string(forType: .string), "transcript two")
        scheduledRestores[1].action()
        XCTAssertEqual(pasteboard.string(forType: .string), "original two")
    }

    func testFallsBackToClipboardWhenPasteShortcutCannotBePosted() async {
        let pasteboard = makePasteboard()
        let defaults = isolatedDefaults()
        var shortcutPostCount = 0
        let service = ClipboardBatchOutput(
            logger: PersonalScribeLogger(category: PersonalScribeLogCategory.ui),
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
                return false
            }
        )

        let result = await service.deliverBatch(text: "shortcut fallback")

        XCTAssertEqual(result, .delivered(target: .frontmostApp, delivery: .clipboardOnly))
        XCTAssertEqual(shortcutPostCount, 1)
        XCTAssertEqual(pasteboard.string(forType: .string), "shortcut fallback")
    }

    func testClipboardOnlyWriteFailureRestoresExistingPasteboardContents() async {
        let defaults = isolatedDefaults()
        PasteMode.preference(defaults: defaults).persist(.clipboardOnly)
        let pasteboard = makePasteboard()
        pasteboard.clearContents()
        _ = pasteboard.setString("existing value", forType: .string)
        var shortcutPostCount = 0
        let service = ClipboardBatchOutput(
            logger: PersonalScribeLogger(category: PersonalScribeLogCategory.ui),
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
            },
            writeString: { _, _ in false }
        )

        let result = await service.deliverBatch(text: "new value")

        XCTAssertEqual(result, .failed(.clipboardWriteFailed))
        XCTAssertEqual(shortcutPostCount, 0)
        XCTAssertEqual(pasteboard.string(forType: .string), "existing value")
    }
}

@MainActor
private struct FakeFrontmostAppProvider: FrontmostAppProviding {
    let frontmostApplicationBundleIdentifier: String?
}
