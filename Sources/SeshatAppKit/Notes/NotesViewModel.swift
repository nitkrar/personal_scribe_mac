import Combine
import Foundation
import SeshatCore

@MainActor
final class NotesViewModel: ObservableObject {
    @Published private(set) var entries: [TranscriptEntry] = []
    @Published private(set) var selectedEntryID: UUID?
    @Published private(set) var searchQuery = ""
    @Published private(set) var isSearching = false

    private let transcriptReader: any TranscriptReading

    init(transcriptReader: any TranscriptReading) {
        self.transcriptReader = transcriptReader
    }

    var selectedEntry: TranscriptEntry? {
        guard let selectedEntryID else {
            return nil
        }

        return entries.first { $0.id == selectedEntryID }
    }

    /// Phase 3 history lists the entire transcript store newest-first.
    /// The action keeps its historical name so the step contract stays
    /// stable while the backing reader returns the full collection.
    func loadRecent() async {
        searchQuery = ""
        isSearching = false
        replaceEntries(with: await transcriptReader.all())
    }

    func search(query: String) async {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            await loadRecent()
            return
        }

        searchQuery = trimmedQuery
        isSearching = true
        replaceEntries(with: await transcriptReader.search(query: trimmedQuery))
    }

    func select(id: UUID?) {
        selectedEntryID = id
    }

    private func replaceEntries(with newEntries: [TranscriptEntry]) {
        entries = newEntries

        guard let selectedEntryID else {
            self.selectedEntryID = newEntries.first?.id
            return
        }

        if newEntries.contains(where: { $0.id == selectedEntryID }) {
            self.selectedEntryID = selectedEntryID
        } else {
            self.selectedEntryID = newEntries.first?.id
        }
    }
}
