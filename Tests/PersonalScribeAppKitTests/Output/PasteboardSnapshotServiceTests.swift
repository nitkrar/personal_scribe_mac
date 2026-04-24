import AppKit
import XCTest
@testable import PersonalScribeAppKit

@MainActor
final class PasteboardSnapshotServiceTests: XCTestCase {
    /// In-memory fake backing the injected closures. Tracks items + a
    /// bump-on-write `changeCount` counter so `restoreSnapshotIfUnchanged`
    /// can be exercised without a real `NSPasteboard`.
    private final class FakePasteboard {
        var items: [NSPasteboardItem] = []
        var changeCount: Int = 0

        func writeItems(_ newItems: [NSPasteboardItem]) {
            items = newItems
            changeCount += 1
        }

        func writeString(_ string: String) -> Bool {
            let item = NSPasteboardItem()
            item.setString(string, forType: .string)
            items = [item]
            changeCount += 1
            return true
        }
    }

    private func makeService(
        backing: FakePasteboard,
        failStringWrite: Bool = false
    ) -> PasteboardSnapshotService {
        PasteboardSnapshotService(
            itemsReader: { backing.items },
            itemsWriter: { items in backing.writeItems(items) },
            stringWriter: { string in
                if failStringWrite { return false }
                return backing.writeString(string)
            },
            changeCountReader: { backing.changeCount }
        )
    }

    private func putString(_ string: String, on backing: FakePasteboard) {
        _ = backing.writeString(string)
    }

    private func firstString(on backing: FakePasteboard) -> String? {
        backing.items.first?.string(forType: .string)
    }

    // MARK: - Transient handles (1.1–1.5)

    func testCaptureTransientSnapshotRoundTripsFullItemFidelity() {
        let backing = FakePasteboard()
        // Put two types on the clipboard simultaneously — plain string + RTF.
        let item = NSPasteboardItem()
        item.setString("hello world", forType: .string)
        item.setData(Data("rtf payload".utf8), forType: .rtf)
        backing.items = [item]

        let service = makeService(backing: backing)
        let handle = service.captureTransientSnapshot()

        // Overwrite.
        putString("transcript overwrote it", on: backing)

        let didRestore = service.restoreSnapshot(handle)

        XCTAssertTrue(didRestore)
        XCTAssertEqual(backing.items.count, 1)
        XCTAssertEqual(backing.items.first?.string(forType: .string), "hello world")
        XCTAssertEqual(backing.items.first?.data(forType: .rtf), Data("rtf payload".utf8))
    }

    func testRestoreTransientSnapshotConsumesHandle() {
        let backing = FakePasteboard()
        putString("user clipboard", on: backing)
        let service = makeService(backing: backing)
        let handle = service.captureTransientSnapshot()

        putString("transcript", on: backing)
        XCTAssertTrue(service.restoreSnapshot(handle))
        XCTAssertEqual(firstString(on: backing), "user clipboard")

        // Write something new; second restore must not clobber it.
        putString("user typed something new", on: backing)
        let changeCountBefore = backing.changeCount
        let second = service.restoreSnapshot(handle)

        XCTAssertFalse(second)
        XCTAssertEqual(firstString(on: backing), "user typed something new")
        XCTAssertEqual(backing.changeCount, changeCountBefore, "No write on second restore")
    }

    func testTwoTransientHandlesRestoreIndependently() {
        let backing = FakePasteboard()
        putString("A", on: backing)
        let service = makeService(backing: backing)
        let handleA = service.captureTransientSnapshot()

        putString("B", on: backing)
        let handleB = service.captureTransientSnapshot()

        putString("something else entirely", on: backing)

        XCTAssertTrue(service.restoreSnapshot(handleA))
        XCTAssertEqual(firstString(on: backing), "A")

        XCTAssertTrue(service.restoreSnapshot(handleB))
        XCTAssertEqual(firstString(on: backing), "B")
    }

    func testDiscardConsumesTransientHandleWithoutWriting() {
        let backing = FakePasteboard()
        putString("user clipboard", on: backing)
        let service = makeService(backing: backing)
        let handle = service.captureTransientSnapshot()

        putString("transcript", on: backing)
        let changeCountBefore = backing.changeCount
        service.discardSnapshot(handle)

        XCTAssertEqual(firstString(on: backing), "transcript")
        XCTAssertEqual(backing.changeCount, changeCountBefore, "Discard must not write")

        // Subsequent restore is a no-op.
        XCTAssertFalse(service.restoreSnapshot(handle))
    }

    func testCaptureEmptyPasteboardRestoresToEmpty() {
        let backing = FakePasteboard()
        // Empty clipboard at capture time.
        XCTAssertTrue(backing.items.isEmpty)
        let service = makeService(backing: backing)
        let handle = service.captureTransientSnapshot()

        putString("transcript", on: backing)
        XCTAssertEqual(firstString(on: backing), "transcript")

        XCTAssertTrue(service.restoreSnapshot(handle))
        XCTAssertTrue(backing.items.isEmpty, "Restoring an empty snapshot clears the pasteboard")
    }

    // MARK: - Durable slot: .cancelUndo (1.6, 1.7)

    func testCaptureIntoCancelUndoSlotAndRestore() {
        let backing = FakePasteboard()
        putString("pre-recording", on: backing)
        let service = makeService(backing: backing)

        service.captureCurrentContents(into: .cancelUndo)
        putString("transcript", on: backing)

        let restored = service.restoreSnapshot(from: .cancelUndo)

        XCTAssertTrue(restored)
        XCTAssertEqual(firstString(on: backing), "pre-recording")
    }

    func testRestoreFromCancelUndoSlotConsumesSlot() {
        let backing = FakePasteboard()
        putString("pre-recording", on: backing)
        let service = makeService(backing: backing)
        service.captureCurrentContents(into: .cancelUndo)

        _ = service.restoreSnapshot(from: .cancelUndo)

        putString("user typed new thing", on: backing)
        let changeCountBefore = backing.changeCount

        let second = service.restoreSnapshot(from: .cancelUndo)

        XCTAssertFalse(second)
        XCTAssertEqual(firstString(on: backing), "user typed new thing")
        XCTAssertEqual(backing.changeCount, changeCountBefore)
    }

    func testClearSnapshotInCancelUndoSlotDiscardsWithoutWriting() {
        let backing = FakePasteboard()
        putString("pre-recording", on: backing)
        let service = makeService(backing: backing)
        service.captureCurrentContents(into: .cancelUndo)

        putString("transcript", on: backing)
        let changeCountBefore = backing.changeCount
        service.clearSnapshot(in: .cancelUndo)

        XCTAssertEqual(firstString(on: backing), "transcript")
        XCTAssertEqual(backing.changeCount, changeCountBefore)
        XCTAssertFalse(service.restoreSnapshot(from: .cancelUndo))
    }

    func testCaptureIntoSlotOverwritesPrevious() {
        let backing = FakePasteboard()
        putString("first", on: backing)
        let service = makeService(backing: backing)
        service.captureCurrentContents(into: .cancelUndo)

        putString("second", on: backing)
        service.captureCurrentContents(into: .cancelUndo)

        // Overwrite with transcript, then restore — must see "second".
        putString("transcript", on: backing)
        XCTAssertTrue(service.restoreSnapshot(from: .cancelUndo))
        XCTAssertEqual(firstString(on: backing), "second")
    }

    func testCancelUndoSlotPreservesNonStringItems() {
        let backing = FakePasteboard()
        let item = NSPasteboardItem()
        item.setString("plain", forType: .string)
        item.setData(Data("rtf bytes".utf8), forType: .rtf)
        backing.items = [item]

        let service = makeService(backing: backing)
        service.captureCurrentContents(into: .cancelUndo)
        putString("transcript", on: backing)

        XCTAssertTrue(service.restoreSnapshot(from: .cancelUndo))
        XCTAssertEqual(backing.items.first?.string(forType: .string), "plain")
        XCTAssertEqual(backing.items.first?.data(forType: .rtf), Data("rtf bytes".utf8))
    }

    // MARK: - Write boundary (1.8)

    func testReplaceContentsWritesTranscriptAndReturnsToken() {
        let backing = FakePasteboard()
        putString("user clipboard", on: backing)
        let service = makeService(backing: backing)

        let token = service.replaceContents(with: "transcript")

        XCTAssertNotNil(token)
        XCTAssertEqual(firstString(on: backing), "transcript")
    }

    func testReplaceContentsReturnsNilOnWriteFailure() {
        let backing = FakePasteboard()
        putString("user clipboard", on: backing)
        let service = makeService(backing: backing, failStringWrite: true)

        let token = service.replaceContents(with: "transcript")

        XCTAssertNil(token)
        XCTAssertEqual(firstString(on: backing), "user clipboard", "No write means no change")
    }

    // MARK: - Guarded restore (1.9) — API lands unused in Step 1

    func testRestoreIfUnchangedRestoresWhenChangeCountMatches() {
        let backing = FakePasteboard()
        putString("user clipboard", on: backing)
        let service = makeService(backing: backing)
        let handle = service.captureTransientSnapshot()

        let token = service.replaceContents(with: "transcript")
        XCTAssertNotNil(token)
        // No external write between replaceContents and the guarded restore.

        let restored = service.restoreSnapshotIfUnchanged(handle, token: token!)

        XCTAssertTrue(restored)
        XCTAssertEqual(firstString(on: backing), "user clipboard")
    }

    func testRestoreIfUnchangedSkipsWhenChangeCountBumped() {
        let backing = FakePasteboard()
        putString("user clipboard", on: backing)
        let service = makeService(backing: backing)
        let handle = service.captureTransientSnapshot()

        let token = service.replaceContents(with: "transcript")
        XCTAssertNotNil(token)

        // Simulate something else writing to the pasteboard (another recording,
        // user Cmd+C, other app).
        putString("intervening write", on: backing)

        let restored = service.restoreSnapshotIfUnchanged(handle, token: token!)

        XCTAssertFalse(restored)
        XCTAssertEqual(firstString(on: backing), "intervening write", "Guard must not clobber")
    }

    func testRestoreIfUnchangedConsumesHandleInBothBranches() {
        let backing = FakePasteboard()
        putString("user clipboard", on: backing)
        let service = makeService(backing: backing)

        // Branch A — match.
        let handleA = service.captureTransientSnapshot()
        let tokenA = service.replaceContents(with: "transcript A")!
        XCTAssertTrue(service.restoreSnapshotIfUnchanged(handleA, token: tokenA))
        // Second call with consumed handle: no-op.
        XCTAssertFalse(service.restoreSnapshotIfUnchanged(handleA, token: tokenA))

        // Branch B — mismatch.
        putString("user clipboard 2", on: backing)
        let handleB = service.captureTransientSnapshot()
        let tokenB = service.replaceContents(with: "transcript B")!
        putString("intervening", on: backing)
        XCTAssertFalse(service.restoreSnapshotIfUnchanged(handleB, token: tokenB))
        // Handle must be consumed even on mismatch.
        XCTAssertFalse(service.restoreSnapshotIfUnchanged(handleB, token: tokenB))
    }
}
