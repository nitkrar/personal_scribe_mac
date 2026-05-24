import Combine
import Foundation
import PersonalScribeCore

/// View model backing the Transcriptions tab of the unified window
/// (M3.2). Exposes the full transcript history (via `TranscriptReading`)
/// with case-insensitive search filtering and date-bucketed grouping
/// ("TODAY" / "YESTERDAY" / compact uppercased "APR 17" calendar dates
/// for older entries).
///
/// Clock injection is deliberate — grouping logic needs a stable "now"
/// so tests can pin the calendar relative to fixture timestamps.
@MainActor
final class TranscriptionsTabViewModel: ObservableObject {
    @Published var entries: [TranscriptEntry] = []
    @Published var searchText: String = ""

    private let reader: any TranscriptReading
    private let deleter: (any TranscriptDeleting)?
    private let updater: (any TranscriptUpdating)?
    private let offlineRetranscriptionAction: OfflineRetranscriptionAction?
    private let clock: @MainActor () -> Date
    private let calendar: Calendar
    private let explicitDateFormatter: DateFormatter
    private let notificationCenter: NotificationCenter
    private var activeLimit: Int = 100
    private var transcriptCommitObservation: NSObjectProtocol?
    private var retranscriptionObservation: AnyCancellable?

    init(
        reader: any TranscriptReading,
        deleter: (any TranscriptDeleting)? = nil,
        updater: (any TranscriptUpdating)? = nil,
        offlineRetranscriptionAction: OfflineRetranscriptionAction? = nil,
        clock: @escaping @MainActor () -> Date = { Date() },
        calendar: Calendar = .autoupdatingCurrent,
        locale: Locale = Locale(identifier: "en_US_POSIX"),
        notificationCenter: NotificationCenter = .default
    ) {
        self.reader = reader
        self.deleter = deleter ?? (reader as? any TranscriptDeleting)
        self.updater = updater ?? (reader as? any TranscriptUpdating)
        self.offlineRetranscriptionAction = offlineRetranscriptionAction
        self.clock = clock
        self.calendar = calendar
        self.notificationCenter = notificationCenter

        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = locale
        // Locale-aware compact month + day (e.g. "Apr 17") — matches the
        // mockup (`plans/App UI design/screen_transcriptions.png`). The
        // bucket is uppercased downstream, producing "APR 17".
        formatter.setLocalizedDateFormatFromTemplate("MMMd")
        self.explicitDateFormatter = formatter

        transcriptCommitObservation = notificationCenter.addObserver(
            forName: MetricsNotification.transcriptCommit,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.reloadEntries()
            }
        }

        retranscriptionObservation = offlineRetranscriptionAction?.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async {
                guard let self else { return }
                MainActor.assumeIsolated {
                    self.objectWillChange.send()
                }
            }
        }
    }

    /// Load the most-recent `limit` entries from the reader. Default 100
    /// matches §3B guidance for the Transcriptions tab surface.
    func load(limit: Int = 100) async {
        activeLimit = limit
        await reloadEntries()
    }

    /// Delete the persisted transcript for `id`, then reload the current
    /// storage-backed window so the published list reflects SQLite rather
    /// than only trimming the in-memory cache.
    func delete(id: UUID) async throws {
        guard let deleter else {
            return
        }

        try await deleter.delete(id: id)
        await reloadEntries()
    }

    var canDelete: Bool {
        deleter != nil
    }

    /// Persist an edited transcript body, then reload the active storage
    /// window so the published list reflects the repository's canonical state.
    func update(id: UUID, text: String) async throws {
        guard let updater else {
            return
        }

        try await updater.update(id: id, text: text)
        await reloadEntries()
    }

    var canEdit: Bool {
        updater != nil
    }

    func showsRetranscribeIcon(for entry: TranscriptEntry) -> Bool {
        guard offlineRetranscriptionAction != nil,
              let audioFilename = entry.audioFilename,
              !audioFilename.isEmpty else {
            return false
        }
        return true
    }

    func isRetranscribing(_ entry: TranscriptEntry) -> Bool {
        guard let sourceFilename = entry.audioFilename,
              !sourceFilename.isEmpty else {
            return false
        }
        return offlineRetranscriptionAction?.busySourceFilenames.contains(sourceFilename) ?? false
    }

    func reTranscribe(_ entry: TranscriptEntry) async {
        guard let sourceFilename = entry.audioFilename,
              !sourceFilename.isEmpty else {
            return
        }

        await offlineRetranscriptionAction?.performRetranscription(sourceFilename: sourceFilename)
    }

    /// Case-insensitive contains-match against `entry.text`. An empty or
    /// whitespace-only search returns all entries unchanged.
    var filteredEntries: [TranscriptEntry] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return entries }

        let needle = trimmed.lowercased()
        return entries.filter { entry in
            entry.text.lowercased().contains(needle)
        }
    }

    /// Group the filtered entries by date-bucket label relative to
    /// `clock()`:
    ///
    /// * Same calendar day as now → `"TODAY"`
    /// * Previous calendar day → `"YESTERDAY"`
    /// * Older → uppercased locale-aware `"MMM d"` (e.g. `"APR 17"`)
    ///
    /// Ordering: TODAY first, then YESTERDAY, then older buckets in
    /// descending chronological order (newest older-bucket first).
    /// Within a bucket, entries are newest-first — preserving the
    /// reader's recent-first ordering.
    var groupedByDate: [(bucket: String, entries: [TranscriptEntry])] {
        let now = clock()
        let startOfToday = calendar.startOfDay(for: now)
        guard let startOfYesterday = calendar.date(byAdding: .day, value: -1, to: startOfToday) else {
            return []
        }

        var todayEntries: [TranscriptEntry] = []
        var yesterdayEntries: [TranscriptEntry] = []
        // `olderBuckets` is keyed by start-of-day so the ordering step
        // can sort by real date rather than the rendered string.
        var olderBuckets: [(dayStart: Date, entries: [TranscriptEntry])] = []

        for entry in filteredEntries {
            let entryDayStart = calendar.startOfDay(for: entry.timestamp)

            if entryDayStart == startOfToday {
                todayEntries.append(entry)
            } else if entryDayStart == startOfYesterday {
                yesterdayEntries.append(entry)
            } else {
                if let index = olderBuckets.firstIndex(where: { $0.dayStart == entryDayStart }) {
                    olderBuckets[index].entries.append(entry)
                } else {
                    olderBuckets.append((dayStart: entryDayStart, entries: [entry]))
                }
            }
        }

        // Older buckets sorted newest-first.
        olderBuckets.sort { $0.dayStart > $1.dayStart }

        var result: [(bucket: String, entries: [TranscriptEntry])] = []

        if !todayEntries.isEmpty {
            result.append((bucket: "TODAY", entries: todayEntries))
        }

        if !yesterdayEntries.isEmpty {
            result.append((bucket: "YESTERDAY", entries: yesterdayEntries))
        }

        for older in olderBuckets {
            let label = explicitDateFormatter.string(from: older.dayStart).uppercased()
            result.append((bucket: label, entries: older.entries))
        }

        return result
    }

    isolated deinit {
        if let transcriptCommitObservation {
            notificationCenter.removeObserver(transcriptCommitObservation)
        }
    }

    private func reloadEntries() async {
        entries = await reader.recent(limit: activeLimit)
    }
}
