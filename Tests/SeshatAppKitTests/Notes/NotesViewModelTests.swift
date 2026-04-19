import XCTest
import SeshatCore
@testable import SeshatAppKit

@MainActor
final class NotesViewModelTests: XCTestCase {
    func testLoadRecentPopulatesEntries() async {
        let older = makeEntry(index: 1, text: "older")
        let newer = makeEntry(index: 2, text: "newer")
        let reader = FakeTranscriptReader(
            allEntries: [newer, older],
            searchResultsByQuery: [:]
        )
        let viewModel = NotesViewModel(transcriptReader: reader)

        await viewModel.loadRecent()

        XCTAssertEqual(viewModel.entries, [newer, older])
        XCTAssertEqual(viewModel.selectedEntryID, newer.id)
        XCTAssertFalse(viewModel.isSearching)
        XCTAssertEqual(viewModel.searchQuery, "")
    }

    func testSearchFiltersEntries() async {
        let older = makeEntry(index: 1, text: "older")
        let newer = makeEntry(index: 2, text: "moon result")
        let reader = FakeTranscriptReader(
            allEntries: [newer, older],
            searchResultsByQuery: ["moon": [newer]]
        )
        let viewModel = NotesViewModel(transcriptReader: reader)

        await viewModel.search(query: " moon ")

        XCTAssertEqual(viewModel.entries, [newer])
        XCTAssertEqual(viewModel.selectedEntryID, newer.id)
        XCTAssertEqual(viewModel.searchQuery, "moon")
        XCTAssertTrue(viewModel.isSearching)
        XCTAssertEqual(await reader.recordedSearchQueries(), ["moon"])
    }

    func testSelectUpdatesSelectedEntryID() async {
        let older = makeEntry(index: 1, text: "older")
        let newer = makeEntry(index: 2, text: "newer")
        let reader = FakeTranscriptReader(
            allEntries: [newer, older],
            searchResultsByQuery: [:]
        )
        let viewModel = NotesViewModel(transcriptReader: reader)
        await viewModel.loadRecent()

        viewModel.select(id: older.id)

        XCTAssertEqual(viewModel.selectedEntryID, older.id)
        XCTAssertEqual(viewModel.selectedEntry, older)
    }

    func testSearchWithEmptyQueryFallsBackToRecent() async {
        let older = makeEntry(index: 1, text: "older")
        let newer = makeEntry(index: 2, text: "moon result")
        let reader = FakeTranscriptReader(
            allEntries: [newer, older],
            searchResultsByQuery: ["moon": [newer]]
        )
        let viewModel = NotesViewModel(transcriptReader: reader)

        await viewModel.search(query: "moon")
        await viewModel.search(query: "   ")

        XCTAssertEqual(viewModel.entries, [newer, older])
        XCTAssertEqual(viewModel.selectedEntryID, newer.id)
        XCTAssertEqual(viewModel.searchQuery, "")
        XCTAssertFalse(viewModel.isSearching)
        XCTAssertEqual(await reader.recordedSearchQueries(), ["moon"])
        XCTAssertEqual(await reader.allCallCount(), 1)
    }

    private func makeEntry(index: Int, text: String) -> TranscriptEntry {
        TranscriptEntry(
            id: UUID(),
            timestamp: Date(timeIntervalSince1970: TimeInterval(index * 60)),
            text: text,
            audioDuration: TimeInterval(index) * 2,
            processingDuration: TimeInterval(index) * 0.5
        )
    }
}

private actor FakeTranscriptReader: TranscriptReading {
    let allEntries: [TranscriptEntry]
    let searchResultsByQuery: [String: [TranscriptEntry]]

    private var searchQueries: [String] = []
    private var allRequests = 0

    init(
        allEntries: [TranscriptEntry],
        searchResultsByQuery: [String: [TranscriptEntry]]
    ) {
        self.allEntries = allEntries
        self.searchResultsByQuery = searchResultsByQuery
    }

    func recent(limit: Int) async -> [TranscriptEntry] {
        Array(allEntries.prefix(limit))
    }

    func search(query: String) async -> [TranscriptEntry] {
        searchQueries.append(query)
        return searchResultsByQuery[query, default: []]
    }

    func all() async -> [TranscriptEntry] {
        allRequests += 1
        return allEntries
    }

    func recordedSearchQueries() -> [String] {
        searchQueries
    }

    func allCallCount() -> Int {
        allRequests
    }
}
