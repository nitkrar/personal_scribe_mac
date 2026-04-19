import XCTest
@testable import SeshatAppKit

@MainActor
final class NotesEditorTests: XCTestCase {
    func testShowsSelectedEntryText() {
        let entry = makeNotesEntry(
            index: 1,
            text: "Quarterly review notes\nPrepare slides and send recap."
        )
        let editor = NotesEditor(selectedEntry: entry)

        XCTAssertEqual(editor.displayText, entry.text)
        XCTAssertFalse(editor.isShowingEmptyState)
    }

    func testEmptySelectionState() {
        let editor = NotesEditor(selectedEntry: nil)

        XCTAssertEqual(editor.displayText, "")
        XCTAssertTrue(editor.isShowingEmptyState)
        XCTAssertEqual(editor.placeholderText, "Select a transcript to view its text.")
    }
}
