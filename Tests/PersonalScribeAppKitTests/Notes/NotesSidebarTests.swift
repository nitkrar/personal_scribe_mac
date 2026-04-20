import XCTest
@testable import PersonalScribeAppKit

@MainActor
final class NotesSidebarTests: XCTestCase {
    func testRowsMapFromViewModelEntries() async {
        let first = makeNotesEntry(
            index: 1,
            text: "Budget review\nAction items and follow-up"
        )
        let second = makeNotesEntry(
            index: 2,
            text: "Standup notes"
        )
        let viewModel = makeNotesViewModel(entries: [second, first])
        await viewModel.loadRecent()

        let sidebar = NotesSidebar(viewModel: viewModel)

        XCTAssertEqual(
            sidebar.rowModels,
            [
                .init(
                    id: second.id,
                    title: "Standup notes",
                    timestamp: second.timestamp,
                    preview: "Standup notes",
                    isSelected: true
                ),
                .init(
                    id: first.id,
                    title: "Budget review",
                    timestamp: first.timestamp,
                    preview: "Action items and follow-up",
                    isSelected: false
                ),
            ]
        )
    }

    func testSelectionBindingUpdatesViewModel() async {
        let first = makeNotesEntry(index: 1, text: "Budget review")
        let second = makeNotesEntry(index: 2, text: "Standup notes")
        let viewModel = makeNotesViewModel(entries: [second, first])
        await viewModel.loadRecent()
        let sidebar = NotesSidebar(viewModel: viewModel)

        sidebar.selection.wrappedValue = first.id

        XCTAssertEqual(viewModel.selectedEntryID, first.id)
    }
}
