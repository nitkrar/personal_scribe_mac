import AppKit
import XCTest
import PersonalScribeCore
import PersonalScribeSession
@testable import PersonalScribeAppKit

@MainActor
final class LiveCursorOutputTests: XCTestCase {
    private final class MutableBoolBox: @unchecked Sendable {
        var value: Bool

        init(_ value: Bool) {
            self.value = value
        }
    }

    private func makePasteboard() -> NSPasteboard {
        NSPasteboard(name: NSPasteboard.Name(rawValue: "personal_scribe.test.\(UUID().uuidString)"))
    }

    private func makeSnapshotService(
        for pasteboard: NSPasteboard,
        stringWriter: ((String) -> Bool)? = nil
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
                if let stringWriter {
                    return stringWriter(string)
                }
                pasteboard.clearContents()
                return pasteboard.setString(string, forType: .string)
            },
            changeCountReader: { pasteboard.changeCount }
        )
    }

    private func makeOutput(
        pasteboard: NSPasteboard,
        logger: PersonalScribeLogger = PersonalScribeLogger.testing(
            category: PersonalScribeLogCategory.ui
        ),
        snapshotService: PasteboardSnapshotService? = nil,
        isAccessibilityTrusted: @escaping @MainActor () -> Bool = { true },
        pasteShortcutPoster: @escaping @MainActor () -> Bool = { true },
        focusedElementIsInAnotherApp: @escaping @MainActor () -> Bool = { true }
    ) -> LiveCursorOutput {
        LiveCursorOutput(
            logger: logger,
            snapshotService: snapshotService ?? makeSnapshotService(for: pasteboard),
            isAccessibilityTrusted: isAccessibilityTrusted,
            pasteShortcutPoster: pasteShortcutPoster,
            focusedElementIsInAnotherApp: focusedElementIsInAnotherApp
        )
    }

    private func makeProgress(_ text: String, revision: Int = 1) -> TranscriptProgress {
        TranscriptProgress(
            revision: revision,
            text: text,
            isFinal: false,
            sourceStage: .transcription
        )
    }

    func testFirstDeliverPartialWritesChunkAndPostsPaste() async throws {
        let pasteboard = makePasteboard()
        pasteboard.clearContents()
        pasteboard.setString("user-pre-session", forType: .string)
        var pasteCount = 0
        let output = makeOutput(
            pasteboard: pasteboard,
            pasteShortcutPoster: {
                pasteCount += 1
                return true
            }
        )

        try await output.deliverPartial(makeProgress("hello"))

        XCTAssertEqual(pasteboard.string(forType: .string), "hello")
        XCTAssertEqual(pasteCount, 1)
    }

    func testDeliverPartialOverwritesPriorChunkOnClipboard() async throws {
        let pasteboard = makePasteboard()
        let output = makeOutput(pasteboard: pasteboard)

        try await output.deliverPartial(makeProgress("hello", revision: 1))
        try await output.deliverPartial(makeProgress("world", revision: 2))

        // #098: subsequent chunks prepend a single space so consecutive
        // EoU pastes don't concatenate. Clipboard ends with the second
        // chunk's payload (with leading space), not just "world".
        XCTAssertEqual(pasteboard.string(forType: .string), " world")
    }

    func testFirstChunkPastesUnchangedSecondChunkPrependsSpace() async throws {
        // #098: explicit guarantee that the chunk separator only kicks
        // in from the second chunk onward. Avoids leading-space on the
        // very first paste at session start.
        let pasteboard = makePasteboard()
        let output = makeOutput(pasteboard: pasteboard)

        try await output.deliverPartial(makeProgress("hello", revision: 1))
        XCTAssertEqual(pasteboard.string(forType: .string), "hello")

        try await output.deliverPartial(makeProgress("world", revision: 2))
        XCTAssertEqual(pasteboard.string(forType: .string), " world")

        try await output.deliverPartial(makeProgress("how are you", revision: 3))
        XCTAssertEqual(pasteboard.string(forType: .string), " how are you")
    }

    func testResetForNewSessionResetsChunkSeparatorGate() async throws {
        // #098: a new session starts the chunk counter fresh — first
        // chunk of session 2 pastes without a leading space even
        // though session 1 had written multiple chunks.
        let pasteboard = makePasteboard()
        let output = makeOutput(pasteboard: pasteboard)

        try await output.deliverPartial(makeProgress("hello", revision: 1))
        try await output.deliverPartial(makeProgress("world", revision: 2))
        await output.endSession()

        await output.resetForNewSession()
        try await output.deliverPartial(makeProgress("fresh", revision: 1))
        XCTAssertEqual(pasteboard.string(forType: .string), "fresh")
    }

    func testDeliverPartialSkipsPasteWhenAxNotTrusted() async throws {
        let pasteboard = makePasteboard()
        var pasteCount = 0
        let output = makeOutput(
            pasteboard: pasteboard,
            isAccessibilityTrusted: { false },
            pasteShortcutPoster: {
                pasteCount += 1
                return true
            }
        )

        try await output.deliverPartial(makeProgress("hello"))

        XCTAssertEqual(pasteboard.string(forType: .string), "hello")
        XCTAssertEqual(pasteCount, 0)
    }

    func testEndSessionEmitsPasteSessionSummaryWithCorrectCounts() async throws {
        let pasteboard = makePasteboard()
        let sink = InMemoryTestSink()
        let logger = makeLogger(sink: sink)
        var writeAttempts = 0
        let snapshotService = makeSnapshotService(
            for: pasteboard,
            stringWriter: { string in
                writeAttempts += 1
                guard writeAttempts < 4 else { return false }
                pasteboard.clearContents()
                return pasteboard.setString(string, forType: .string)
            }
        )
        let output = makeOutput(
            pasteboard: pasteboard,
            logger: logger,
            snapshotService: snapshotService
        )

        await output.resetForNewSession()
        try await output.deliverPartial(makeProgress("one", revision: 1))
        try await output.deliverPartial(makeProgress("two", revision: 2))
        try await output.deliverPartial(makeProgress("three", revision: 3))
        try await output.deliverPartial(makeProgress("four", revision: 4))
        await output.endSession()

        let summaryMessages = await waitForLogMessages(
            in: sink,
            containing: "paste_session_summary",
            expectedCount: 1
        )
        let summary = try XCTUnwrap(summaryMessages.last)
        XCTAssertEqual(summary.level, .info)
        XCTAssertTrue(summary.message.contains("sink=live"))
        XCTAssertTrue(summary.message.contains("livePasteAttempts=4"))
        XCTAssertTrue(summary.message.contains("livePasteSucceeded=3"))
        XCTAssertTrue(summary.message.contains("livePasteFailed=1"))
        XCTAssertTrue(summary.message.contains("livePasteSkipped=0"))
        // #098: chars-written counts the with-separator payload.
        // "one"(3) + " two"(4) + " three"(6) = 13. The 4th attempt
        // failed via stringWriter returning false; nothing added.
        XCTAssertTrue(summary.message.contains("livePasteCumulativeCharsWritten=13"))
        XCTAssertTrue(summary.message.contains("finalPasteAttempted=false"))
        XCTAssertTrue(summary.message.contains("finalPasteSucceeded=false"))
    }

    func testReplaceContentsFailureEmitsPasteFailedErrorAndIncrementsFailedCount() async throws {
        let pasteboard = makePasteboard()
        let sink = InMemoryTestSink()
        let logger = makeLogger(sink: sink)
        let snapshotService = makeSnapshotService(
            for: pasteboard,
            stringWriter: { _ in false }
        )
        let output = makeOutput(
            pasteboard: pasteboard,
            logger: logger,
            snapshotService: snapshotService
        )

        await output.resetForNewSession()
        try await output.deliverPartial(makeProgress("hello"))
        await output.endSession()

        let failureMessages = await waitForLogMessages(
            in: sink,
            containing: "paste_failed — sink=live stage=live reason=pasteboardWriteFailed attemptedChars=5",
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
        XCTAssertTrue(summary.message.contains("livePasteFailed=1"))
        XCTAssertTrue(summary.message.contains("livePasteSucceeded=0"))
    }

    func testPasteShortcutPosterFailureEmitsPasteFailedErrorAndIncrementsFailedCount() async throws {
        let pasteboard = makePasteboard()
        let sink = InMemoryTestSink()
        let logger = makeLogger(sink: sink)
        let output = makeOutput(
            pasteboard: pasteboard,
            logger: logger,
            pasteShortcutPoster: { false }
        )

        await output.resetForNewSession()
        try await output.deliverPartial(makeProgress("hello"))
        await output.endSession()

        let failureMessages = await waitForLogMessages(
            in: sink,
            containing: "paste_failed — sink=live stage=live reason=eventPostFailed attemptedChars=5",
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
        XCTAssertTrue(summary.message.contains("livePasteFailed=1"))
        XCTAssertTrue(summary.message.contains("livePasteCumulativeCharsWritten=5"))
    }

    func testAccessibilityNotTrustedIncrementsSkippedNotFailed() async throws {
        let pasteboard = makePasteboard()
        let sink = InMemoryTestSink()
        let logger = makeLogger(sink: sink)
        let output = makeOutput(
            pasteboard: pasteboard,
            logger: logger,
            isAccessibilityTrusted: { false }
        )

        await output.resetForNewSession()
        try await output.deliverPartial(makeProgress("hello"))
        await output.endSession()

        let summaryMessages = await waitForLogMessages(
            in: sink,
            containing: "paste_session_summary",
            expectedCount: 1
        )
        let summary = try XCTUnwrap(summaryMessages.last)
        XCTAssertTrue(summary.message.contains("livePasteSkipped=1"))
        XCTAssertTrue(summary.message.contains("livePasteFailed=0"))
        XCTAssertTrue(summary.message.contains("livePasteCumulativeCharsWritten=5"))
    }

    func testFocusedSelfIncrementsSkippedNotFailed() async throws {
        let pasteboard = makePasteboard()
        let sink = InMemoryTestSink()
        let logger = makeLogger(sink: sink)
        let output = makeOutput(
            pasteboard: pasteboard,
            logger: logger,
            focusedElementIsInAnotherApp: { false }
        )

        await output.resetForNewSession()
        try await output.deliverPartial(makeProgress("hello"))
        await output.endSession()

        let summaryMessages = await waitForLogMessages(
            in: sink,
            containing: "paste_session_summary",
            expectedCount: 1
        )
        let summary = try XCTUnwrap(summaryMessages.last)
        XCTAssertTrue(summary.message.contains("livePasteSkipped=1"))
        XCTAssertTrue(summary.message.contains("livePasteFailed=0"))
        XCTAssertTrue(summary.message.contains("livePasteCumulativeCharsWritten=5"))
    }

    func testDeliverPartialLogsAccessibilityTrustSkipOncePerClearCycle() async throws {
        let pasteboard = makePasteboard()
        let sink = InMemoryTestSink()
        let logger = makeLogger(sink: sink)
        var pasteCount = 0
        let trustState = MutableBoolBox(false)
        let output = makeOutput(
            pasteboard: pasteboard,
            logger: logger,
            isAccessibilityTrusted: { trustState.value },
            pasteShortcutPoster: {
                pasteCount += 1
                return true
            }
        )

        try await output.deliverPartial(makeProgress("hello", revision: 1))
        try await output.deliverPartial(makeProgress("world", revision: 2))

        _ = await waitForLogMessages(
            in: sink,
            containing: "Accessibility not trusted",
            expectedCount: 1
        )
        try? await Task.sleep(for: .milliseconds(50))
        let firstAxSkipCount = await logMessages(
            in: sink,
            containing: "Accessibility not trusted"
        ).count
        XCTAssertEqual(firstAxSkipCount, 1)

        trustState.value = true
        try await output.deliverPartial(makeProgress("trusted", revision: 3))
        XCTAssertEqual(pasteCount, 1)

        trustState.value = false
        try await output.deliverPartial(makeProgress("again", revision: 4))
        _ = await waitForLogMessages(
            in: sink,
            containing: "Accessibility not trusted",
            expectedCount: 2
        )
        try? await Task.sleep(for: .milliseconds(50))
        let secondAxSkipCount = await logMessages(
            in: sink,
            containing: "Accessibility not trusted"
        ).count
        XCTAssertEqual(secondAxSkipCount, 2)
    }

    func testDeliverPartialSkipsPasteWhenFocusInSelf() async throws {
        let pasteboard = makePasteboard()
        var pasteCount = 0
        let output = makeOutput(
            pasteboard: pasteboard,
            pasteShortcutPoster: {
                pasteCount += 1
                return true
            },
            focusedElementIsInAnotherApp: { false }
        )

        try await output.deliverPartial(makeProgress("hello"))

        XCTAssertEqual(pasteboard.string(forType: .string), "hello")
        XCTAssertEqual(pasteCount, 0)
    }

    func testDeliverPartialIgnoresBlankText() async throws {
        let pasteboard = makePasteboard()
        pasteboard.clearContents()
        pasteboard.setString("user-pre-session", forType: .string)
        var pasteCount = 0
        let output = makeOutput(
            pasteboard: pasteboard,
            pasteShortcutPoster: {
                pasteCount += 1
                return true
            }
        )

        try await output.deliverPartial(makeProgress("   "))

        XCTAssertEqual(pasteboard.string(forType: .string), "user-pre-session")
        XCTAssertEqual(pasteCount, 0)
    }

    func testResetForNewSessionCapturesClipboardBeforeFirstChunkArrives() async throws {
        let pasteboard = makePasteboard()
        pasteboard.clearContents()
        pasteboard.setString("user-pre-session", forType: .string)
        let output = makeOutput(pasteboard: pasteboard)

        await output.resetForNewSession()

        // Simulate the user copying something else after recording starts
        // but before the first EOU chunk lands.
        pasteboard.clearContents()
        pasteboard.setString("copied-during-recording-before-first-chunk", forType: .string)

        try await output.deliverPartial(makeProgress("hello"))
        XCTAssertEqual(pasteboard.string(forType: .string), "hello")

        await output.endSession()

        XCTAssertEqual(
            pasteboard.string(forType: .string),
            "user-pre-session",
            "Live cursor restore must use the session-start snapshot, not clipboard contents captured on first chunk"
        )
    }

    func testEndSessionRestoresPreSessionClipboard() async throws {
        let pasteboard = makePasteboard()
        pasteboard.clearContents()
        pasteboard.setString("user-pre-session", forType: .string)
        let output = makeOutput(pasteboard: pasteboard)

        try await output.deliverPartial(makeProgress("hello"))
        XCTAssertEqual(pasteboard.string(forType: .string), "hello")

        await output.endSession()

        XCTAssertEqual(pasteboard.string(forType: .string), "user-pre-session")
    }

    func testEndSessionWithoutDeliveriesIsNoOp() async throws {
        let pasteboard = makePasteboard()
        pasteboard.clearContents()
        pasteboard.setString("user-pre-session", forType: .string)
        let output = makeOutput(pasteboard: pasteboard)

        await output.endSession()

        XCTAssertEqual(pasteboard.string(forType: .string), "user-pre-session")
    }

    func testEndSessionWithoutChunkWritesPreservesMidSessionClipboardChange() async throws {
        let pasteboard = makePasteboard()
        pasteboard.clearContents()
        pasteboard.setString("user-pre-session", forType: .string)
        let output = makeOutput(pasteboard: pasteboard)

        await output.resetForNewSession()

        // Simulates a non-streaming (or live-cursor-disabled) session where
        // the orchestrator still brackets the sink lifecycle, but no EOU chunk
        // was ever written by this sink. A user clipboard change during the
        // session must survive cancel/short-exit teardown.
        pasteboard.clearContents()
        pasteboard.setString("copied-during-session", forType: .string)

        await output.endSession()

        XCTAssertEqual(
            pasteboard.string(forType: .string),
            "copied-during-session",
            "endSession must not restore a session-start snapshot when no live cursor chunk was written"
        )
    }

    func testEndSessionTwiceRestoresOnceOnly() async throws {
        let pasteboard = makePasteboard()
        pasteboard.clearContents()
        pasteboard.setString("user-pre-session", forType: .string)
        let output = makeOutput(pasteboard: pasteboard)

        try await output.deliverPartial(makeProgress("hello"))
        await output.endSession()
        XCTAssertEqual(pasteboard.string(forType: .string), "user-pre-session")

        // External actor changes the clipboard between sessions.
        pasteboard.clearContents()
        pasteboard.setString("manual-paste-after-restore", forType: .string)

        await output.endSession()

        XCTAssertEqual(
            pasteboard.string(forType: .string),
            "manual-paste-after-restore",
            "Second endSession() must NOT restore (snapshot was already consumed)"
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

    func testDeliverFinalIsNoOp() async throws {
        let pasteboard = makePasteboard()
        pasteboard.clearContents()
        pasteboard.setString("user-pre-session", forType: .string)
        let output = makeOutput(pasteboard: pasteboard)

        try await output.deliverFinal(
            TranscriptionResult(
                text: "ignored",
                audioDuration: .seconds(1),
                processingDuration: .milliseconds(10)
            )
        )

        XCTAssertEqual(pasteboard.string(forType: .string), "user-pre-session")
    }

    func testResetForNewSessionDiscardsStaleHandleWithoutRestoring() async throws {
        let pasteboard = makePasteboard()
        pasteboard.clearContents()
        pasteboard.setString("user-pre-session", forType: .string)
        let output = makeOutput(pasteboard: pasteboard)

        // Set up a session that captured a snapshot but never reached endSession.
        try await output.deliverPartial(makeProgress("hello"))
        XCTAssertEqual(pasteboard.string(forType: .string), "hello")

        // Imagine the orchestrator skipped endSession and went straight to
        // resetForNewSession on the next start. The defensive path should
        // drop the handle without restoring (we don't know what's on the
        // clipboard now).
        await output.resetForNewSession()

        // Subsequent endSession should now be a no-op (handle was discarded).
        await output.endSession()

        XCTAssertEqual(
            pasteboard.string(forType: .string),
            "hello",
            "resetForNewSession should NOT restore the snapshot; subsequent endSession should be a no-op"
        )
    }
}
