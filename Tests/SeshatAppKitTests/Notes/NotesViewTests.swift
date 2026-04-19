import XCTest
@testable import SeshatAppKit

@MainActor
final class NotesViewTests: XCTestCase {
    func testSelectedEntryFlowsIntoEditorAndContextPanel() async {
        let first = makeNotesEntry(index: 1, text: "Budget review")
        let second = makeNotesEntry(index: 2, text: "Standup notes")
        let viewModel = makeNotesViewModel(entries: [second, first])
        await viewModel.loadRecent()
        viewModel.select(id: first.id)

        let view = NotesView(viewModel: viewModel)

        XCTAssertEqual(view.editor.displayText, first.text)
        XCTAssertEqual(view.contextPanel.metadataItems.count, 3)
        XCTAssertEqual(view.contextPanel.metadataItems[1].value, "0:02")
    }

    func testSearchFieldBindingDelegatesToViewModel() async {
        let match = makeNotesEntry(index: 1, text: "moon meeting")
        let other = makeNotesEntry(index: 2, text: "standup")
        let viewModel = makeNotesViewModel(
            entries: [other, match],
            searchResultsByQuery: ["moon": [match]]
        )
        let view = NotesView(viewModel: viewModel)

        view.searchFieldBinding.wrappedValue = " moon "
        await waitUntil { viewModel.searchQuery == "moon" }

        XCTAssertEqual(viewModel.entries, [match])
        XCTAssertTrue(viewModel.isSearching)
        XCTAssertEqual(view.searchFieldPrompt, "Search history")
    }

    private func waitUntil(
        timeoutIterations: Int = 20,
        condition: @escaping @MainActor () -> Bool
    ) async {
        for _ in 0..<timeoutIterations {
            if condition() {
                return
            }

            await Task.yield()
        }

        XCTFail("Condition was not met before the wait loop finished")
    }
}
