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
            },
            focusedElementHasCursor: { true }
        )

        let result = await service.deliverBatch(text: "hello world")

        XCTAssertEqual(result, .delivered(target: .clipboardOnly, delivery: .clipboardOnly))
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
            },
            focusedElementHasCursor: { true }
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
            },
            focusedElementHasCursor: { true }
        )

        let result = await service.deliverBatch(text: "clipboard only")

        XCTAssertEqual(result, .delivered(target: .clipboardOnly, delivery: .clipboardOnly))
        XCTAssertEqual(shortcutPostCount, 0)
        XCTAssertEqual(pasteboard.string(forType: .string), "clipboard only")
    }

    // Re-targeted from `testDeliverBatchReturnsClipboardOnlyWhenFrontmostAppIsPersonalScribe`:
    // Under the new design (2026-04-20), the frontmost bundle-ID check is dropped because
    // clicking Ninimma's pill/menu momentarily flipped NSWorkspace's frontmost app to self
    // and caused spurious `.selfFrontmost` outcomes. We now consult the focused-element
    // cursor probe instead — even when the reported frontmost app is Ninimma, if the AX
    // focused element (which lives in whatever the user's text cursor is actually in) has a
    // cursor, we paste.
    func testDeliverBatchPastesWhenFrontmostIsSelfButFocusedElementHasCursor() async {
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
            },
            focusedElementHasCursor: { true }
        )

        let result = await service.deliverBatch(text: "self frontmost but cursor present")

        XCTAssertEqual(result, .delivered(target: .frontmostApp, delivery: .paste))
        XCTAssertEqual(shortcutPostCount, 1)
        XCTAssertEqual(pasteboard.string(forType: .string), "self frontmost but cursor present")
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
            },
            focusedElementHasCursor: { true }
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
            pasteShortcutPoster: { _ in true },
            focusedElementHasCursor: { true }
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
            },
            focusedElementHasCursor: { true }
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
            writeString: { _, _ in false },
            focusedElementHasCursor: { true }
        )

        let result = await service.deliverBatch(text: "new value")

        XCTAssertEqual(result, .failed(.clipboardWriteFailed))
        XCTAssertEqual(shortcutPostCount, 0)
        XCTAssertEqual(pasteboard.string(forType: .string), "existing value")
    }

    // MARK: - Focused-element cursor probe (2026-04-20 redesign)

    func testDeliverBatchPastesWhenFocusedElementHasCursor() async {
        let pasteboard = makePasteboard()
        let defaults = isolatedDefaults()
        var shortcutPostCount = 0
        var cursorProbeCount = 0
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
            focusedElementHasCursor: {
                cursorProbeCount += 1
                return true
            }
        )

        let result = await service.deliverBatch(text: "cursor present")

        XCTAssertEqual(result, .delivered(target: .frontmostApp, delivery: .paste))
        XCTAssertEqual(shortcutPostCount, 1)
        XCTAssertEqual(cursorProbeCount, 1)
        XCTAssertEqual(pasteboard.string(forType: .string), "cursor present")
    }

    func testDeliverBatchSkipsPasteWhenFocusedElementHasNoCursor_ReturnsClipboardOnly() async {
        let pasteboard = makePasteboard()
        let defaults = isolatedDefaults()
        var shortcutPostCount = 0
        var cursorProbeCount = 0
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
            focusedElementHasCursor: {
                cursorProbeCount += 1
                return false
            }
        )

        let result = await service.deliverBatch(text: "no cursor")

        XCTAssertEqual(result, .delivered(target: .clipboardOnly, delivery: .clipboardOnly))
        XCTAssertEqual(shortcutPostCount, 0, "paste shortcut must not be posted when focused element has no cursor")
        XCTAssertEqual(cursorProbeCount, 1)
        XCTAssertEqual(pasteboard.string(forType: .string), "no cursor")
    }

    func testDeliverBatchAlwaysWritesToClipboardEvenWhenPasteSkipped() async {
        let pasteboard = makePasteboard()
        let defaults = isolatedDefaults()
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
            pasteShortcutPoster: { _ in true },
            focusedElementHasCursor: { false }
        )

        let result = await service.deliverBatch(text: "written regardless")

        XCTAssertEqual(result, .delivered(target: .clipboardOnly, delivery: .clipboardOnly))
        XCTAssertEqual(
            pasteboard.string(forType: .string),
            "written regardless",
            "clipboard must always receive the transcript, even when paste is skipped"
        )
    }

    func testFocusedElementCheckIsNotConsultedWhenPasteModeIsClipboardOnly() async {
        let defaults = isolatedDefaults()
        PasteMode.preference(defaults: defaults).persist(.clipboardOnly)
        let pasteboard = makePasteboard()
        var cursorProbeCount = 0
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
            pasteShortcutPoster: { _ in true },
            focusedElementHasCursor: {
                cursorProbeCount += 1
                return true
            }
        )

        let result = await service.deliverBatch(text: "clipboard-only mode")

        XCTAssertEqual(result, .delivered(target: .clipboardOnly, delivery: .clipboardOnly))
        XCTAssertEqual(cursorProbeCount, 0, "focused-element probe must be skipped when user picked clipboard-only mode")
        XCTAssertEqual(pasteboard.string(forType: .string), "clipboard-only mode")
    }

    func testFocusedElementCheckIsNotConsultedWhenAccessibilityDenied() async {
        let pasteboard = makePasteboard()
        let defaults = isolatedDefaults()
        var cursorProbeCount = 0
        var promptCount = 0
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
            pasteShortcutPoster: { _ in true },
            focusedElementHasCursor: {
                cursorProbeCount += 1
                return true
            }
        )

        let result = await service.deliverBatch(text: "ax denied")

        XCTAssertEqual(result, .delivered(target: .clipboardOnly, delivery: .clipboardOnly))
        XCTAssertEqual(cursorProbeCount, 0, "focused-element probe must be skipped when Accessibility is not trusted")
        XCTAssertEqual(promptCount, 1)
        XCTAssertEqual(pasteboard.string(forType: .string), "ax denied")
    }
}

@MainActor
private struct FakeFrontmostAppProvider: FrontmostAppProviding {
    let frontmostApplicationBundleIdentifier: String?
}
