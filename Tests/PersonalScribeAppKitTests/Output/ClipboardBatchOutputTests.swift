import AppKit
import XCTest
import PersonalScribeCore
@testable import PersonalScribeAppKit

@MainActor
final class ClipboardBatchOutputTests: XCTestCase {
    private let suiteName = "PersonalScribeTestsClipboardBatchOutput"

    /// #089 L-24: tests now drive `deliverBatch` via the session-frozen
    /// sink list instead of UserDefaults flags. These helpers map
    /// pre-#089 scenarios (auto-paste on/off, restore on/off) onto the
    /// post-#089 `[BoundOutputSink]` shape.
    private static func sinks(
        autoPaste: Bool = true,
        restoreEnabled: Bool = false
    ) -> [BoundOutputSink] {
        [
            .clipboard(restoreEnabled: restoreEnabled),
            .frontmostPaste(enabled: autoPaste),
            .transcriptHistorySQLite,
        ]
    }

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

    private func makeLogger(sink: InMemoryTestSink) -> PersonalScribeLogger {
        PersonalScribeLogger(
            category: PersonalScribeLogCategory.ui,
            reporter: DiagnosticsReporter(
                sinks: [sink],
                now: { Date(timeIntervalSince1970: 0) }
            )
        )
    }

    private func waitForLogMessages(
        in sink: InMemoryTestSink,
        containing fragment: String,
        expectedCount: Int
    ) async -> [RedactedDiagnosticsEvent] {
        for _ in 0..<100 {
            let messages = await logMessages(in: sink, containing: fragment)
            if messages.count >= expectedCount {
                return messages
            }
            try? await Task.sleep(for: .milliseconds(10))
        }

        XCTFail("Timed out waiting for \(expectedCount) diagnostics messages containing '\(fragment)'")
        return await logMessages(in: sink, containing: fragment)
    }

    private func logMessages(
        in sink: InMemoryTestSink,
        containing fragment: String
    ) async -> [RedactedDiagnosticsEvent] {
        await sink.snapshot().filter { $0.message.contains(fragment) }
    }

    func testPromptsAccessibilityWhenNotTrustedAndLeavesTranscriptOnClipboard() async {
        let pasteboard = makePasteboard()
        let defaults = isolatedDefaults()
        var promptCount = 0
        var shortcutPostCount = 0
        let service = ClipboardBatchOutput(
            logger: PersonalScribeLogger.testing(category: PersonalScribeLogCategory.ui),
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

        let result = await service.deliverBatch(text: "hello world", sinks: Self.sinks())

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
            logger: PersonalScribeLogger.testing(category: PersonalScribeLogCategory.ui),
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

        let result = await service.deliverBatch(text: "already trusted", sinks: Self.sinks())

        XCTAssertEqual(result, .delivered(target: .frontmostApp, delivery: .paste))
        XCTAssertEqual(promptCount, 0)
        XCTAssertEqual(shortcutPostCount, 1)
    }

    func testDeliverBatchEmitsPasteSessionSummaryOnSuccessPath() async throws {
        let pasteboard = makePasteboard()
        let defaults = isolatedDefaults()
        let sink = InMemoryTestSink()
        let logger = makeLogger(sink: sink)
        let service = ClipboardBatchOutput(
            logger: logger,
            defaults: defaults,
            frontmostAppProvider: FakeFrontmostAppProvider(
                frontmostApplicationBundleIdentifier: "com.apple.TextEdit"
            ),
            snapshotService: makeSnapshotService(for: pasteboard),
            scheduleRestore: { _, _ in },
            isAccessibilityTrusted: { true },
            requestAccessibilityPrompt: {},
            pasteShortcutPoster: { _ in true },
            focusedElementIsInAnotherApp: { true }
        )

        let result = await service.deliverBatch(text: "already trusted", sinks: Self.sinks())

        XCTAssertEqual(result, .delivered(target: .frontmostApp, delivery: .paste))
        let summaryMessages = await waitForLogMessages(
            in: sink,
            containing: "paste_session_summary",
            expectedCount: 1
        )
        let summary = try XCTUnwrap(summaryMessages.last)
        XCTAssertEqual(summary.level, .info)
        XCTAssertTrue(summary.message.contains("sink=batch"))
        XCTAssertTrue(summary.message.contains("finalPasteAttempted=true"))
        XCTAssertTrue(summary.message.contains("finalPasteSucceeded=true"))
        XCTAssertTrue(summary.message.contains("finalPasteCharsWritten=15"))
        XCTAssertTrue(summary.message.contains("finalPasteFailureReason=nil"))
        XCTAssertTrue(summary.message.contains("finalPasteSkipped=false"))
    }

    func testDeliverBatchWithAutoPasteDisabledRecordsClipboardOnlyNotSucceeded() async throws {
        let pasteboard = makePasteboard()
        let defaults = isolatedDefaults()
        let sink = InMemoryTestSink()
        let logger = makeLogger(sink: sink)
        let service = ClipboardBatchOutput(
            logger: logger,
            defaults: defaults,
            frontmostAppProvider: FakeFrontmostAppProvider(
                frontmostApplicationBundleIdentifier: "com.apple.TextEdit"
            ),
            snapshotService: makeSnapshotService(for: pasteboard),
            scheduleRestore: { _, _ in },
            isAccessibilityTrusted: { true },
            requestAccessibilityPrompt: {},
            pasteShortcutPoster: { _ in true },
            focusedElementIsInAnotherApp: { true }
        )

        let result = await service.deliverBatch(text: "clipboard only", sinks: Self.sinks(autoPaste: false))

        XCTAssertEqual(result, .delivered(target: .clipboardOnly, delivery: .clipboardOnly))
        let summaryMessages = await waitForLogMessages(
            in: sink,
            containing: "paste_session_summary",
            expectedCount: 1
        )
        let summary = try XCTUnwrap(summaryMessages.last)
        XCTAssertTrue(summary.message.contains("finalPasteSucceeded=false"))
        XCTAssertTrue(summary.message.contains("finalPasteSkipped=true"))
        XCTAssertTrue(summary.message.contains("finalPasteCharsWritten=14"))
    }

    func testDeliverBatchEmitsPasteFailedErrorAndSetsFinalFailureReasonWhenPasteboardWriteFails() async throws {
        let pasteboard = makePasteboard()
        let defaults = isolatedDefaults()
        let sink = InMemoryTestSink()
        let logger = makeLogger(sink: sink)
        let service = ClipboardBatchOutput(
            logger: logger,
            defaults: defaults,
            frontmostAppProvider: FakeFrontmostAppProvider(
                frontmostApplicationBundleIdentifier: "com.apple.TextEdit"
            ),
            snapshotService: makeSnapshotService(for: pasteboard, failStringWrite: true),
            scheduleRestore: { _, _ in },
            isAccessibilityTrusted: { true },
            requestAccessibilityPrompt: {},
            pasteShortcutPoster: { _ in true },
            focusedElementIsInAnotherApp: { true }
        )

        let result = await service.deliverBatch(text: "new value", sinks: Self.sinks(autoPaste: false))

        XCTAssertEqual(result, .failed(.clipboardWriteFailed))
        let failureMessages = await waitForLogMessages(
            in: sink,
            containing: "paste_failed — sink=batch stage=final reason=pasteboardWriteFailed attemptedChars=9",
            expectedCount: 1
        )
        let failure = try XCTUnwrap(failureMessages.last)
        XCTAssertEqual(failure.level, .error)

        let summaryMessages = await waitForLogMessages(
            in: sink,
            containing: "paste_session_summary",
            expectedCount: 1
        )
        let summary = try XCTUnwrap(summaryMessages.last)
        XCTAssertTrue(summary.message.contains("finalPasteSucceeded=false"))
        XCTAssertTrue(summary.message.contains("finalPasteCharsWritten=0"))
        XCTAssertTrue(summary.message.contains("finalPasteFailureReason=pasteboardWriteFailed"))
        XCTAssertTrue(summary.message.contains("finalPasteSkipped=false"))
    }

    func testDeliverBatchEmitsPasteFailedErrorAndSetsFinalFailureReasonWhenAccessibilityNotTrusted() async throws {
        let pasteboard = makePasteboard()
        let defaults = isolatedDefaults()
        let sink = InMemoryTestSink()
        let logger = makeLogger(sink: sink)
        var promptCount = 0
        let service = ClipboardBatchOutput(
            logger: logger,
            defaults: defaults,
            frontmostAppProvider: FakeFrontmostAppProvider(
                frontmostApplicationBundleIdentifier: "com.apple.TextEdit"
            ),
            snapshotService: makeSnapshotService(for: pasteboard),
            scheduleRestore: { _, _ in },
            isAccessibilityTrusted: { false },
            requestAccessibilityPrompt: { promptCount += 1 },
            pasteShortcutPoster: { _ in true },
            focusedElementIsInAnotherApp: { true }
        )

        let result = await service.deliverBatch(text: "hello world", sinks: Self.sinks())

        XCTAssertEqual(result, .delivered(target: .clipboardOnly, delivery: .clipboardOnly))
        XCTAssertEqual(promptCount, 1)
        let failureMessages = await waitForLogMessages(
            in: sink,
            containing: "paste_failed — sink=batch stage=final reason=accessibilityNotTrusted attemptedChars=11",
            expectedCount: 1
        )
        let failure = try XCTUnwrap(failureMessages.last)
        XCTAssertEqual(failure.level, .error)

        let summaryMessages = await waitForLogMessages(
            in: sink,
            containing: "paste_session_summary",
            expectedCount: 1
        )
        let summary = try XCTUnwrap(summaryMessages.last)
        XCTAssertTrue(summary.message.contains("finalPasteSucceeded=false"))
        XCTAssertTrue(summary.message.contains("finalPasteCharsWritten=11"))
        XCTAssertTrue(summary.message.contains("finalPasteFailureReason=accessibilityNotTrusted"))
        XCTAssertTrue(summary.message.contains("finalPasteSkipped=false"))
    }

    func testDeliverBatchReturnsClipboardOnlyWhenAutoPasteDisabled() async {
        let defaults = isolatedDefaults()
        // #089: auto-paste is now a per-mode sink toggle, not a defaults flag.
        let pasteboard = makePasteboard()
        var shortcutPostCount = 0
        let service = ClipboardBatchOutput(
            logger: PersonalScribeLogger.testing(category: PersonalScribeLogCategory.ui),
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

        let result = await service.deliverBatch(text: "clipboard only", sinks: Self.sinks(autoPaste: false))

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
        let pasteboard = makePasteboard()
        var shortcutPostCount = 0
        let service = ClipboardBatchOutput(
            logger: PersonalScribeLogger.testing(category: PersonalScribeLogCategory.ui),
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

        let result = await service.deliverBatch(text: "self frontmost but cursor present", sinks: Self.sinks())

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
            logger: PersonalScribeLogger.testing(category: PersonalScribeLogCategory.ui),
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

        let result = await service.deliverBatch(text: "", sinks: Self.sinks())

        XCTAssertEqual(result, .ignoredEmptyInput)
        XCTAssertEqual(promptCount, 0)
        XCTAssertEqual(shortcutPostCount, 0)
        XCTAssertEqual(pasteboard.string(forType: .string), "prior")
    }

    func testDeliverBatchReadsRestoreDelayPreferencePerCall() async {
        let pasteboard = makePasteboard()
        let defaults = isolatedDefaults()
        // #089: restore-enabled is now a sink parameter; this test
        // exercises the scheduled-restore path, so turn it on in sinks.
        var scheduledRestores: [(delay: TimeInterval, action: @MainActor () -> Void)] = []
        let service = ClipboardBatchOutput(
            logger: PersonalScribeLogger.testing(category: PersonalScribeLogCategory.ui),
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

        let firstResult = await service.deliverBatch(text: "transcript one", sinks: Self.sinks(restoreEnabled: true))

        XCTAssertEqual(firstResult, .delivered(target: .frontmostApp, delivery: .paste))
        XCTAssertEqual(scheduledRestores.count, 1)
        XCTAssertEqual(scheduledRestores[0].delay, 0.2, accuracy: 0.0001)
        XCTAssertEqual(pasteboard.string(forType: .string), "transcript one")
        scheduledRestores[0].action()
        XCTAssertEqual(pasteboard.string(forType: .string), "original one")

        pasteboard.clearContents()
        _ = pasteboard.setString("original two", forType: .string)
        ClipboardRestoreDelay.storedSeconds(defaults: defaults).persist(1.4)

        let secondResult = await service.deliverBatch(text: "transcript two", sinks: Self.sinks(restoreEnabled: true))

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
        // #089: restore is now expressed in the sink list. Pass
        // restoreEnabled: false explicitly to document intent.
        var scheduledRestores: [(delay: TimeInterval, action: @MainActor () -> Void)] = []
        let service = ClipboardBatchOutput(
            logger: PersonalScribeLogger.testing(category: PersonalScribeLogCategory.ui),
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

        let result = await service.deliverBatch(text: "transcript", sinks: Self.sinks(restoreEnabled: false))

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
        var scheduledRestores: [(delay: TimeInterval, action: @MainActor () -> Void)] = []
        let service = ClipboardBatchOutput(
            logger: PersonalScribeLogger.testing(category: PersonalScribeLogCategory.ui),
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

        let result = await service.deliverBatch(text: "transcript", sinks: Self.sinks(restoreEnabled: true))
        XCTAssertEqual(result, .delivered(target: .frontmostApp, delivery: .paste))
        XCTAssertEqual(scheduledRestores.count, 1)
        XCTAssertEqual(pasteboard.string(forType: .string), "transcript")

        // Simulate something else writing to the clipboard before the timer
        // fires — e.g., a second recording landing Transcript B. The
        // `clearContents()` call is required to bump `NSPasteboard.changeCount`
        // — bare `setString` after a previous `setString` of the same type
        // does not advance the count, so the changeCount-based token guard
        // would not detect the foreign write. Real foreign apps go through
        // `declareTypes`/`clearContents` before writing.
        pasteboard.clearContents()
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
            logger: PersonalScribeLogger.testing(category: PersonalScribeLogCategory.ui),
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

        let result = await service.deliverBatch(text: "shortcut fallback", sinks: Self.sinks())

        XCTAssertEqual(result, .delivered(target: .frontmostApp, delivery: .clipboardOnly))
        XCTAssertEqual(shortcutPostCount, 1)
        XCTAssertEqual(pasteboard.string(forType: .string), "shortcut fallback")
    }

    func testClipboardOnlyWriteFailureRestoresExistingPasteboardContents() async {
        let defaults = isolatedDefaults()
        let pasteboard = makePasteboard()
        pasteboard.clearContents()
        _ = pasteboard.setString("existing value", forType: .string)
        var shortcutPostCount = 0
        let service = ClipboardBatchOutput(
            logger: PersonalScribeLogger.testing(category: PersonalScribeLogCategory.ui),
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

        let result = await service.deliverBatch(text: "new value", sinks: Self.sinks(autoPaste: false))

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
            logger: PersonalScribeLogger.testing(category: PersonalScribeLogCategory.ui),
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

        let result = await service.deliverBatch(text: "cursor present", sinks: Self.sinks())

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
            logger: PersonalScribeLogger.testing(category: PersonalScribeLogCategory.ui),
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

        let result = await service.deliverBatch(text: "no cursor", sinks: Self.sinks())

        XCTAssertEqual(result, .delivered(target: .clipboardOnly, delivery: .clipboardOnly))
        XCTAssertEqual(shortcutPostCount, 0, "paste shortcut must not be posted when focused element is owned by self")
        XCTAssertEqual(probeCount, 1)
        XCTAssertEqual(pasteboard.string(forType: .string), "no cursor")
    }

    func testDeliverBatchAlwaysWritesToClipboardEvenWhenPasteSkipped() async {
        let pasteboard = makePasteboard()
        let defaults = isolatedDefaults()
        let service = ClipboardBatchOutput(
            logger: PersonalScribeLogger.testing(category: PersonalScribeLogCategory.ui),
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

        let result = await service.deliverBatch(text: "written regardless", sinks: Self.sinks())

        XCTAssertEqual(result, .delivered(target: .clipboardOnly, delivery: .clipboardOnly))
        XCTAssertEqual(
            pasteboard.string(forType: .string),
            "written regardless",
            "clipboard must always receive the transcript, even when paste is skipped"
        )
    }

    func testFocusedElementCheckIsNotConsultedWhenAutoPasteDisabled() async {
        let defaults = isolatedDefaults()
        let pasteboard = makePasteboard()
        var probeCount = 0
        let service = ClipboardBatchOutput(
            logger: PersonalScribeLogger.testing(category: PersonalScribeLogCategory.ui),
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

        let result = await service.deliverBatch(text: "clipboard-only mode", sinks: Self.sinks(autoPaste: false))

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
            logger: PersonalScribeLogger.testing(category: PersonalScribeLogCategory.ui),
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

        let result = await service.deliverBatch(text: "ax denied", sinks: Self.sinks())

        XCTAssertEqual(result, .delivered(target: .clipboardOnly, delivery: .clipboardOnly))
        XCTAssertEqual(probeCount, 0, "focused-element probe must be skipped when Accessibility is not trusted")
        XCTAssertEqual(promptCount, 1)
        XCTAssertEqual(pasteboard.string(forType: .string), "ax denied")
    }

    // MARK: - #089 H.6 — sink absence is the feature gate

    /// H.6 — pin the L-24 sink-truth contract. A sink list with paste
    /// but no `.clipboard` entry must NOT touch the pasteboard or
    /// schedule a restore. Codex DESIGN-review-2 §2 caught the
    /// booleans-only API would have clipboard-written here regardless.
    func testDeliverBatchSkipsClipboardWhenNoClipboardSink() async {
        let pasteboard = makePasteboard()
        let defaults = isolatedDefaults()
        pasteboard.clearContents()
        _ = pasteboard.setString("untouched", forType: .string)
        let preChangeCount = pasteboard.changeCount
        var scheduledRestores = 0
        var shortcutPostCount = 0
        let service = ClipboardBatchOutput(
            logger: PersonalScribeLogger.testing(category: PersonalScribeLogCategory.ui),
            defaults: defaults,
            frontmostAppProvider: FakeFrontmostAppProvider(
                frontmostApplicationBundleIdentifier: "com.apple.TextEdit"
            ),
            snapshotService: makeSnapshotService(for: pasteboard),
            scheduleRestore: { _, _ in scheduledRestores += 1 },
            isAccessibilityTrusted: { true },
            requestAccessibilityPrompt: {},
            pasteShortcutPoster: { _ in
                shortcutPostCount += 1
                return true
            },
            focusedElementIsInAnotherApp: { true }
        )

        let result = await service.deliverBatch(
            text: "no clipboard sink",
            sinks: [
                .frontmostPaste(enabled: true),
                .transcriptHistorySQLite,
            ]
        )

        XCTAssertEqual(result, .delivered(target: .clipboardOnly, delivery: .clipboardOnly))
        XCTAssertEqual(pasteboard.string(forType: .string), "untouched",
                       "Pasteboard contents must be untouched when no .clipboard sink is present")
        XCTAssertEqual(pasteboard.changeCount, preChangeCount,
                       "Pasteboard changeCount must not advance — no write occurred")
        XCTAssertEqual(scheduledRestores, 0,
                       "No clipboard sink ⇒ no schedule-restore call")
        XCTAssertEqual(shortcutPostCount, 0,
                       "Paste must not fire when there's no clipboard write to follow")
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

    // MARK: - #098 newline-before-final-paste

    func testFinalPastePrependsNewlineWhenLiveCursorDidPaste() async {
        // #098: live cursor pasted ≥1 chunk this session, paste enabled.
        // ClipboardBatchOutput prepends "\n" so the final paste lands
        // on its own line rather than running into the last live chunk.
        let pasteboard = makePasteboard()
        let defaults = isolatedDefaults()
        let service = ClipboardBatchOutput(
            logger: PersonalScribeLogger.testing(category: PersonalScribeLogCategory.ui),
            defaults: defaults,
            frontmostAppProvider: FakeFrontmostAppProvider(
                frontmostApplicationBundleIdentifier: "com.apple.TextEdit"
            ),
            snapshotService: makeSnapshotService(for: pasteboard),
            scheduleRestore: { _, _ in },
            isAccessibilityTrusted: { true },
            requestAccessibilityPrompt: {},
            pasteShortcutPoster: { _ in true },
            focusedElementIsInAnotherApp: { true },
            liveCursorPasteSnapshot: { 3 }
        )

        let result = await service.deliverBatch(text: "Final paragraph.", sinks: Self.sinks())

        XCTAssertEqual(result, .delivered(target: .frontmostApp, delivery: .paste))
        XCTAssertEqual(pasteboard.string(forType: .string), "\nFinal paragraph.")
    }

    func testFinalPasteDoesNotPrependNewlineWhenLiveCursorDidNotPaste() async {
        // #098: zero live chunks this session (typical short Parakeet
        // session with no EoU fires). No newline.
        let pasteboard = makePasteboard()
        let defaults = isolatedDefaults()
        let service = ClipboardBatchOutput(
            logger: PersonalScribeLogger.testing(category: PersonalScribeLogCategory.ui),
            defaults: defaults,
            frontmostAppProvider: FakeFrontmostAppProvider(
                frontmostApplicationBundleIdentifier: "com.apple.TextEdit"
            ),
            snapshotService: makeSnapshotService(for: pasteboard),
            scheduleRestore: { _, _ in },
            isAccessibilityTrusted: { true },
            requestAccessibilityPrompt: {},
            pasteShortcutPoster: { _ in true },
            focusedElementIsInAnotherApp: { true },
            liveCursorPasteSnapshot: { 0 }
        )

        let result = await service.deliverBatch(text: "Final paragraph.", sinks: Self.sinks())

        XCTAssertEqual(result, .delivered(target: .frontmostApp, delivery: .paste))
        XCTAssertEqual(pasteboard.string(forType: .string), "Final paragraph.")
    }

    func testFinalPasteDoesNotPrependNewlineWhenPasteDisabled() async {
        // #098: live cursor pasted, but auto-paste is OFF in the mode
        // (clipboard-only delivery). No newline — user pastes manually,
        // they don't want a stray leading newline.
        let pasteboard = makePasteboard()
        let defaults = isolatedDefaults()
        let service = ClipboardBatchOutput(
            logger: PersonalScribeLogger.testing(category: PersonalScribeLogCategory.ui),
            defaults: defaults,
            frontmostAppProvider: FakeFrontmostAppProvider(
                frontmostApplicationBundleIdentifier: "com.apple.TextEdit"
            ),
            snapshotService: makeSnapshotService(for: pasteboard),
            scheduleRestore: { _, _ in },
            isAccessibilityTrusted: { true },
            requestAccessibilityPrompt: {},
            pasteShortcutPoster: { _ in true },
            focusedElementIsInAnotherApp: { true },
            liveCursorPasteSnapshot: { 3 }
        )

        let result = await service.deliverBatch(text: "Final paragraph.", sinks: Self.sinks(autoPaste: false))

        XCTAssertEqual(result, .delivered(target: .clipboardOnly, delivery: .clipboardOnly))
        XCTAssertEqual(pasteboard.string(forType: .string), "Final paragraph.")
    }
}

@MainActor
private struct FakeFrontmostAppProvider: FrontmostAppProviding {
    let frontmostApplicationBundleIdentifier: String?
}
