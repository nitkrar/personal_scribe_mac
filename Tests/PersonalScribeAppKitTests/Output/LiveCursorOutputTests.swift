import AppKit
import XCTest
import PersonalScribeCore
import PersonalScribeSession
@testable import PersonalScribeAppKit

@MainActor
final class LiveCursorOutputTests: XCTestCase {
    private func makePasteboard() -> NSPasteboard {
        NSPasteboard(name: NSPasteboard.Name(rawValue: "personal_scribe.test.\(UUID().uuidString)"))
    }

    private func makeSnapshotService(for pasteboard: NSPasteboard) -> PasteboardSnapshotService {
        PasteboardSnapshotService(
            itemsReader: { pasteboard.pasteboardItems ?? [] },
            itemsWriter: { items in
                pasteboard.clearContents()
                if !items.isEmpty {
                    pasteboard.writeObjects(items)
                }
            },
            stringWriter: { string in
                pasteboard.clearContents()
                return pasteboard.setString(string, forType: .string)
            },
            changeCountReader: { pasteboard.changeCount }
        )
    }

    private func makeOutput(
        pasteboard: NSPasteboard,
        isAccessibilityTrusted: @escaping @MainActor () -> Bool = { true },
        pasteShortcutPoster: @escaping @MainActor () -> Bool = { true },
        focusedElementIsInAnotherApp: @escaping @MainActor () -> Bool = { true }
    ) -> LiveCursorOutput {
        LiveCursorOutput(
            logger: PersonalScribeLogger.testing(category: PersonalScribeLogCategory.ui),
            snapshotService: makeSnapshotService(for: pasteboard),
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

        XCTAssertEqual(pasteboard.string(forType: .string), "world")
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
