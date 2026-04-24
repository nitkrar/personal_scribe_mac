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

    /// Builds a `PasteboardSnapshotService` targeting the test-scoped
    /// pasteboard. Reads / writes the real test `NSPasteboard` so existing
    /// end-state assertions (`pasteboard.string(forType: .string)`) keep
    /// working. `failStringWrite: true` simulates the
    /// `ClipboardBatchOutput` pre-#072 `writeString: { _, _ in false }`
    /// injection used by the write-failure rollback test.
    private func makeSnapshotService(
        for pasteboard: NSPasteboard,
        failStringWrite: Bool = false
    ) -> PasteboardSnapshotService {
        PasteboardSnapshotService(
            itemsReader: { pasteboard.pasteboardItems ?? [] },
            itemsWriter: { items in
                pasteboard.clearContents()
                if !items.isEmpty {
                    pasteboard.writeObjects(items)
                }
            },
            stringWriter: { string in
                if failStringWrite { return false }
                pasteboard.clearContents()
                return pasteboard.setString(string, forType: .string)
            },
            changeCountReader: { pasteboard.changeCount }
        )
    }

    func testPromptsAccessibilityWhenNotTrustedAndLeavesTranscriptOnClipboard() async {
        let pasteboard = makePasteboard()
        let defaults = isolatedDefaults()
        var promptCount = 0
        var shortcutPostCount = 0
        let service = ClipboardBatchOutput(
            logger: PersonalScribeLogger(category: PersonalScribeLogCategory.ui),
            defaults: defaults,
            frontmostAppProvider: FakeFrontmostAppProvider(
                frontmostApplicationBundleIdentifier: "com.apple.TextEdit"
            ),
            snapshotService: makeSnapshotService(for: pasteboard),
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
            defaults: defaults,
            frontmostAppProvider: FakeFrontmostAppProvider(
                frontmostApplicationBundleIdentifier: "com.apple.TextEdit"
            ),
            snapshotService: makeSnapshotService(for: pasteboard),
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

    func testDeliverBatchReturnsClipboardOnlyWhenAutoPasteDisabled() async {
        let defaults = isolatedDefaults()
        AutoPasteEnabledPreference.persist(false, to: defaults)
        let pasteboard = makePasteboard()
        var shortcutPostCount = 0
        let service = ClipboardBatchOutput(
            logger: PersonalScribeLogger(category: PersonalScribeLogCategory.ui),
            defaults: defaults,
            frontmostAppProvider: FakeFrontmostAppProvider(
                frontmostApplicationBundleIdentifier: "com.apple.TextEdit"
            ),
            snapshotService: makeSnapshotService(for: pasteboard),
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
        AutoPasteEnabledPreference.persist(true, to: defaults)
        let pasteboard = makePasteboard()
        var shortcutPostCount = 0
        let service = ClipboardBatchOutput(
            logger: PersonalScribeLogger(category: PersonalScribeLogCategory.ui),
            defaults: defaults,
            frontmostAppProvider: FakeFrontmostAppProvider(
                frontmostApplicationBundleIdentifier: "com.nitkrar.personal_scribe"
            ),
            snapshotService: makeSnapshotService(for: pasteboard),
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
            defaults: defaults,
            frontmostAppProvider: FakeFrontmostAppProvider(
                frontmostApplicationBundleIdentifier: "com.apple.TextEdit"
            ),
            snapshotService: makeSnapshotService(for: pasteboard),
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
        // Restore is off by default post-#072; this test specifically
        // exercises the scheduled-restore path, so turn it on.
        ClipboardRestoreEnabledPreference.persist(true, to: defaults)
        var scheduledRestores: [(delay: TimeInterval, action: @MainActor () -> Void)] = []
        let service = ClipboardBatchOutput(
            logger: PersonalScribeLogger(category: PersonalScribeLogCategory.ui),
            defaults: defaults,
            frontmostAppProvider: FakeFrontmostAppProvider(
                frontmostApplicationBundleIdentifier: "com.apple.TextEdit"
            ),
            snapshotService: makeSnapshotService(for: pasteboard),
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
        ClipboardRestoreDelay.storedSeconds(defaults: defaults).persist(0.2)

        let firstResult = await service.deliverBatch(text: "transcript one")

        XCTAssertEqual(firstResult, .delivered(target: .frontmostApp, delivery: .paste))
        XCTAssertEqual(scheduledRestores.count, 1)
        XCTAssertEqual(scheduledRestores[0].delay, 0.2, accuracy: 0.0001)
        XCTAssertEqual(pasteboard.string(forType: .string), "transcript one")
        scheduledRestores[0].action()
        XCTAssertEqual(pasteboard.string(forType: .string), "original one")

        pasteboard.clearContents()
        _ = pasteboard.setString("original two", forType: .string)
        ClipboardRestoreDelay.storedSeconds(defaults: defaults).persist(1.4)

        let secondResult = await service.deliverBatch(text: "transcript two")

        XCTAssertEqual(secondResult, .delivered(target: .frontmostApp, delivery: .paste))
        XCTAssertEqual(scheduledRestores.count, 2)
        XCTAssertEqual(scheduledRestores[1].delay, 1.4, accuracy: 0.0001)
        XCTAssertEqual(pasteboard.string(forType: .string), "transcript two")
        scheduledRestores[1].action()
        XCTAssertEqual(pasteboard.string(forType: .string), "original two")
    }

    // MARK: - #072 restore toggle + changeCount guard

    func testDeliverBatchSkipsScheduledRestoreWhenRestoreDisabled() async {
        let pasteboard = makePasteboard()
        let defaults = isolatedDefaults()
        // Default is OFF; set explicitly to document intent.
        ClipboardRestoreEnabledPreference.persist(false, to: defaults)
        var scheduledRestores: [(delay: TimeInterval, action: @MainActor () -> Void)] = []
        let service = ClipboardBatchOutput(
            logger: PersonalScribeLogger(category: PersonalScribeLogCategory.ui),
            defaults: defaults,
            frontmostAppProvider: FakeFrontmostAppProvider(
                frontmostApplicationBundleIdentifier: "com.apple.TextEdit"
            ),
            snapshotService: makeSnapshotService(for: pasteboard),
            scheduleRestore: { delay, action in
                scheduledRestores.append((delay: delay, action: action))
            },
            isAccessibilityTrusted: { true },
            requestAccessibilityPrompt: {},
            pasteShortcutPoster: { _ in true },
            focusedElementIsInAnotherApp: { true }
        )

        pasteboard.clearContents()
        _ = pasteboard.setString("original", forType: .string)

        let result = await service.deliverBatch(text: "transcript")

        XCTAssertEqual(result, .delivered(target: .frontmostApp, delivery: .paste))
        XCTAssertTrue(
            scheduledRestores.isEmpty,
            "Restore toggle off means no scheduleRestore call — transcript stays on clipboard"
        )
        XCTAssertEqual(pasteboard.string(forType: .string), "transcript")
    }

    func testScheduledRestoreSkipsWhenClipboardChangedSinceWrite() async {
        // #072 changeCount guard: if anything else (new recording, user Cmd+C,
        // another app) wrote to the clipboard between our transcript write
        // and the delayed restore, the restore must NOT clobber that content.
        let pasteboard = makePasteboard()
        let defaults = isolatedDefaults()
        ClipboardRestoreEnabledPreference.persist(true, to: defaults)
        var scheduledRestores: [(delay: TimeInterval, action: @MainActor () -> Void)] = []
        let service = ClipboardBatchOutput(
            logger: PersonalScribeLogger(category: PersonalScribeLogCategory.ui),
            defaults: defaults,
            frontmostAppProvider: FakeFrontmostAppProvider(
                frontmostApplicationBundleIdentifier: "com.apple.TextEdit"
            ),
            snapshotService: makeSnapshotService(for: pasteboard),
            scheduleRestore: { delay, action in
                scheduledRestores.append((delay: delay, action: action))
            },
            isAccessibilityTrusted: { true },
            requestAccessibilityPrompt: {},
            pasteShortcutPoster: { _ in true },
            focusedElementIsInAnotherApp: { true }
        )

        pasteboard.clearContents()
        _ = pasteboard.setString("user original", forType: .string)

        let result = await service.deliverBatch(text: "transcript")
        XCTAssertEqual(result, .delivered(target: .frontmostApp, delivery: .paste))
        XCTAssertEqual(scheduledRestores.count, 1)
        XCTAssertEqual(pasteboard.string(forType: .string), "transcript")

        // Simulate something else writing to the clipboard before the timer
        // fires — e.g., a second recording landing Transcript B.
        _ = pasteboard.setString("something else landed", forType: .string)

        // Timer fires.
        scheduledRestores[0].action()

        XCTAssertEqual(
            pasteboard.string(forType: .string),
            "something else landed",
            "changeCount guard must prevent the restore from clobbering newer content"
        )
    }

    func testFallsBackToClipboardWhenPasteShortcutCannotBePosted() async {
        let pasteboard = makePasteboard()
        let defaults = isolatedDefaults()
        var shortcutPostCount = 0
        let service = ClipboardBatchOutput(
            logger: PersonalScribeLogger(category: PersonalScribeLogCategory.ui),
            defaults: defaults,
            frontmostAppProvider: FakeFrontmostAppProvider(
                frontmostApplicationBundleIdentifier: "com.apple.TextEdit"
            ),
            snapshotService: makeSnapshotService(for: pasteboard),
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
        AutoPasteEnabledPreference.persist(false, to: defaults)
        let pasteboard = makePasteboard()
        pasteboard.clearContents()
        _ = pasteboard.setString("existing value", forType: .string)
        var shortcutPostCount = 0
        let service = ClipboardBatchOutput(
            logger: PersonalScribeLogger(category: PersonalScribeLogCategory.ui),
            defaults: defaults,
            frontmostAppProvider: FakeFrontmostAppProvider(
                frontmostApplicationBundleIdentifier: "com.apple.TextEdit"
            ),
            snapshotService: makeSnapshotService(for: pasteboard, failStringWrite: true),
            scheduleRestore: { _, _ in },
            isAccessibilityTrusted: { true },
            requestAccessibilityPrompt: {},
            pasteShortcutPoster: { _ in
                shortcutPostCount += 1
                return true
            },
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
            defaults: defaults,
            frontmostAppProvider: FakeFrontmostAppProvider(
                frontmostApplicationBundleIdentifier: "com.apple.TextEdit"
            ),
            snapshotService: makeSnapshotService(for: pasteboard),
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
            defaults: defaults,
            frontmostAppProvider: FakeFrontmostAppProvider(
                frontmostApplicationBundleIdentifier: "com.apple.TextEdit"
            ),
            snapshotService: makeSnapshotService(for: pasteboard),
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
            defaults: defaults,
            frontmostAppProvider: FakeFrontmostAppProvider(
                frontmostApplicationBundleIdentifier: "com.apple.TextEdit"
            ),
            snapshotService: makeSnapshotService(for: pasteboard),
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

    func testFocusedElementCheckIsNotConsultedWhenAutoPasteDisabled() async {
        let defaults = isolatedDefaults()
        AutoPasteEnabledPreference.persist(false, to: defaults)
        let pasteboard = makePasteboard()
        var probeCount = 0
        let service = ClipboardBatchOutput(
            logger: PersonalScribeLogger(category: PersonalScribeLogCategory.ui),
            defaults: defaults,
            frontmostAppProvider: FakeFrontmostAppProvider(
                frontmostApplicationBundleIdentifier: "com.apple.TextEdit"
            ),
            snapshotService: makeSnapshotService(for: pasteboard),
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
        XCTAssertEqual(probeCount, 0, "focused-element probe must be skipped when auto-paste is disabled")
        XCTAssertEqual(pasteboard.string(forType: .string), "clipboard-only mode")
    }

    func testFocusedElementCheckIsNotConsultedWhenAccessibilityDenied() async {
        let pasteboard = makePasteboard()
        let defaults = isolatedDefaults()
        var probeCount = 0
        var promptCount = 0
        let service = ClipboardBatchOutput(
            logger: PersonalScribeLogger(category: PersonalScribeLogCategory.ui),
            defaults: defaults,
            frontmostAppProvider: FakeFrontmostAppProvider(
                frontmostApplicationBundleIdentifier: "com.apple.TextEdit"
            ),
            snapshotService: makeSnapshotService(for: pasteboard),
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
