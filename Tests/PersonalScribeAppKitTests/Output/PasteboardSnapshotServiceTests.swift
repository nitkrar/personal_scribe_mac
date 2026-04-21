import AppKit
import XCTest
@testable import PersonalScribeAppKit

@MainActor
final class PasteboardSnapshotServiceTests: XCTestCase {
    private final class InMemoryPasteboard {
        var string: String?
    }

    private func makeService(
        backing: InMemoryPasteboard
    ) -> PasteboardSnapshotService {
        PasteboardSnapshotService(
            read: { backing.string },
            write: { backing.string = $0 }
        )
    }

    // MARK: - Snapshot

    func testSnapshotCapturesCurrentPasteboardString() {
        let backing = InMemoryPasteboard()
        backing.string = "user clipboard"
        let service = makeService(backing: backing)

        service.snapshotCurrentContents()

        XCTAssertEqual(service.currentSnapshot, "user clipboard")
    }

    func testSnapshotOfEmptyPasteboardStoresNil() {
        let backing = InMemoryPasteboard()
        backing.string = nil
        let service = makeService(backing: backing)

        service.snapshotCurrentContents()

        XCTAssertNil(service.currentSnapshot)
    }

    func testSecondSnapshotOverwritesFirst() {
        let backing = InMemoryPasteboard()
        backing.string = "first"
        let service = makeService(backing: backing)
        service.snapshotCurrentContents()

        backing.string = "second"
        service.snapshotCurrentContents()

        XCTAssertEqual(service.currentSnapshot, "second")
    }

    // MARK: - Restore

    func testRestoreWritesSavedStringToPasteboard() {
        let backing = InMemoryPasteboard()
        backing.string = "user clipboard"
        let service = makeService(backing: backing)
        service.snapshotCurrentContents()

        backing.string = "transcript that overwrote it"
        let restored = service.restoreLastSnapshot()

        XCTAssertTrue(restored)
        XCTAssertEqual(backing.string, "user clipboard")
    }

    /// After a restore the snapshot is consumed. A second Undo must be
    /// a no-op rather than re-asserting the same stale contents.
    func testRestoreClearsSnapshotAfterUse() {
        let backing = InMemoryPasteboard()
        backing.string = "user clipboard"
        let service = makeService(backing: backing)
        service.snapshotCurrentContents()

        _ = service.restoreLastSnapshot()

        XCTAssertNil(service.currentSnapshot)
        backing.string = "user typed something new"

        let secondRestore = service.restoreLastSnapshot()

        XCTAssertFalse(secondRestore)
        XCTAssertEqual(
            backing.string,
            "user typed something new",
            "Second restore must not clobber new clipboard contents"
        )
    }

    func testRestoreReturnsFalseWhenNoSnapshot() {
        let backing = InMemoryPasteboard()
        backing.string = "untouched"
        let service = makeService(backing: backing)

        let restored = service.restoreLastSnapshot()

        XCTAssertFalse(restored)
        XCTAssertEqual(backing.string, "untouched")
    }

    // MARK: - Clear

    func testClearDiscardsSnapshotWithoutWriting() {
        let backing = InMemoryPasteboard()
        backing.string = "user clipboard"
        let service = makeService(backing: backing)
        service.snapshotCurrentContents()

        backing.string = "transcript"
        service.clearSnapshot()

        XCTAssertNil(service.currentSnapshot)
        XCTAssertEqual(
            backing.string,
            "transcript",
            "Clear must not write to the pasteboard"
        )

        // Subsequent restore is a no-op.
        let restored = service.restoreLastSnapshot()
        XCTAssertFalse(restored)
    }
}
