import Foundation
import SeshatCore
@testable import SeshatAppKit

func makeNotesEntry(
    index: Int,
    text: String,
    audioDuration: TimeInterval? = nil,
    processingDuration: TimeInterval? = nil
) -> TranscriptEntry {
    TranscriptEntry(
        id: UUID(),
        timestamp: Date(timeIntervalSince1970: TimeInterval(index * 60)),
        text: text,
        audioDuration: audioDuration ?? TimeInterval(index) * 2,
        processingDuration: processingDuration ?? TimeInterval(index) * 0.5
    )
}

actor NotesStubTranscriptReader: TranscriptReading {
    let recentEntries: [TranscriptEntry]
    let searchResultsByQuery: [String: [TranscriptEntry]]
    let allEntries: [TranscriptEntry]

    private var searchQueries: [String] = []
    private var allRequests = 0

    init(
        recentEntries: [TranscriptEntry]? = nil,
        searchResultsByQuery: [String: [TranscriptEntry]] = [:],
        allEntries: [TranscriptEntry]
    ) {
        self.recentEntries = recentEntries ?? allEntries
        self.searchResultsByQuery = searchResultsByQuery
        self.allEntries = allEntries
    }

    func recent(limit: Int) async -> [TranscriptEntry] {
        Array(recentEntries.prefix(limit))
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

@MainActor
func makeNotesViewModel(
    entries: [TranscriptEntry],
    searchResultsByQuery: [String: [TranscriptEntry]] = [:],
    recentEntries: [TranscriptEntry]? = nil
) -> NotesViewModel {
    NotesViewModel(
        transcriptReader: NotesStubTranscriptReader(
            recentEntries: recentEntries,
            searchResultsByQuery: searchResultsByQuery,
            allEntries: entries
        )
    )
}
