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
            focusedElementIsInAnotherApp: { true }
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
            focusedElementIsInAnotherApp: { true }
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
            focusedElementIsInAnotherApp: { true }
        )

        let result = await service.deliverBatch(text: "clipboard only")

        XCTAssertEqual(result, .delivered(target: .clipboardOnly, delivery: .clipboardOnly))
        XCTAssertEqual(shortcutPostCount, 0)
        XCTAssertEqual(pasteboard.string(forType: .string), "clipboard only")
    }

    // Under the #042 fix (2026-04-22), the probe asks whether the AX focused element is
    // owned by another process. Even when `NSWorkspace.frontmostApplication` momentarily
    // reports Ninimma (e.g., a status-item menu tracking window), if the real AX focus
    // stayed in the user's target app, paste fires. The frontmost bundle-ID is not on the
    // paste-gating path anymore.
    func testDeliverBatchPastesWhenFrontmostIsSelfButFocusIsInAnotherApp() async {
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
            focusedElementIsInAnotherApp: { true }
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
            focusedElementIsInAnotherApp: { true }
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
            focusedElementIsInAnotherApp: { true }
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
            focusedElementIsInAnotherApp: { true }
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
            focusedElementIsInAnotherApp: { true }
        )

        let result = await service.deliverBatch(text: "new value")

        XCTAssertEqual(result, .failed(.clipboardWriteFailed))
        XCTAssertEqual(shortcutPostCount, 0)
        XCTAssertEqual(pasteboard.string(forType: .string), "existing value")
    }

    // MARK: - Focused-element externality probe (#042, 2026-04-22)

    func testDeliverBatchPastesWhenFocusedElementIsInAnotherApp() async {
        let pasteboard = makePasteboard()
        let defaults = isolatedDefaults()
        var shortcutPostCount = 0
        var probeCount = 0
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
            focusedElementIsInAnotherApp: {
                probeCount += 1
                return true
            }
        )

        let result = await service.deliverBatch(text: "cursor present")

        XCTAssertEqual(result, .delivered(target: .frontmostApp, delivery: .paste))
        XCTAssertEqual(shortcutPostCount, 1)
        XCTAssertEqual(probeCount, 1)
        XCTAssertEqual(pasteboard.string(forType: .string), "cursor present")
    }

    func testDeliverBatchSkipsPasteWhenFocusedElementIsInSelf_ReturnsClipboardOnly() async {
        let pasteboard = makePasteboard()
        let defaults = isolatedDefaults()
        var shortcutPostCount = 0
        var probeCount = 0
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
            focusedElementIsInAnotherApp: {
                probeCount += 1
                return false
            }
        )

        let result = await service.deliverBatch(text: "no cursor")

        XCTAssertEqual(result, .delivered(target: .clipboardOnly, delivery: .clipboardOnly))
        XCTAssertEqual(shortcutPostCount, 0, "paste shortcut must not be posted when focused element is owned by self")
        XCTAssertEqual(probeCount, 1)
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
            focusedElementIsInAnotherApp: { false }
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
        var probeCount = 0
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
            focusedElementIsInAnotherApp: {
                probeCount += 1
                return true
            }
        )

        let result = await service.deliverBatch(text: "clipboard-only mode")

        XCTAssertEqual(result, .delivered(target: .clipboardOnly, delivery: .clipboardOnly))
        XCTAssertEqual(probeCount, 0, "focused-element probe must be skipped when user picked clipboard-only mode")
        XCTAssertEqual(pasteboard.string(forType: .string), "clipboard-only mode")
    }

    func testFocusedElementCheckIsNotConsultedWhenAccessibilityDenied() async {
        let pasteboard = makePasteboard()
        let defaults = isolatedDefaults()
        var probeCount = 0
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
            focusedElementIsInAnotherApp: {
                probeCount += 1
                return true
            }
        )

        let result = await service.deliverBatch(text: "ax denied")

        XCTAssertEqual(result, .delivered(target: .clipboardOnly, delivery: .clipboardOnly))
        XCTAssertEqual(probeCount, 0, "focused-element probe must be skipped when Accessibility is not trusted")
        XCTAssertEqual(promptCount, 1)
        XCTAssertEqual(pasteboard.string(forType: .string), "ax denied")
    }

    // MARK: - Pure PID-comparison helper (#042)

    func testFocusedElementIsInAnotherApp_returnsTrueWhenForeignPID() {
        let result = ClipboardBatchOutput.focusedElementIsInAnotherApp(
            systemWideFocusedPID: { pid_t(12345) },
            currentProcessPID: { pid_t(99999) }
        )
        XCTAssertTrue(result)
    }

    func testFocusedElementIsInAnotherApp_returnsFalseWhenSelfPID() {
        let result = ClipboardBatchOutput.focusedElementIsInAnotherApp(
            systemWideFocusedPID: { pid_t(12345) },
            currentProcessPID: { pid_t(12345) }
        )
        XCTAssertFalse(result)
    }

    func testFocusedElementIsInAnotherApp_returnsFalseWhenNoFocusedElement() {
        let result = ClipboardBatchOutput.focusedElementIsInAnotherApp(
            systemWideFocusedPID: { nil },
            currentProcessPID: { pid_t(99999) }
        )
        XCTAssertFalse(result)
    }
}

@MainActor
private struct FakeFrontmostAppProvider: FrontmostAppProviding {
    let frontmostApplicationBundleIdentifier: String?
}
