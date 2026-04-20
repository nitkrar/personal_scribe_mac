import Combine
import Foundation
import PersonalScribeCore

/// View model backing the Transcriptions tab of the unified window
/// (M3.2). Exposes the full transcript history (via `TranscriptReading`)
/// with case-insensitive search filtering and date-bucketed grouping
/// ("TODAY" / "YESTERDAY" / explicit uppercased "APRIL 17, 2026"
/// calendar dates for older entries).
///
/// Clock injection is deliberate — grouping logic needs a stable "now"
/// so tests can pin the calendar relative to fixture timestamps.
@MainActor
final class TranscriptionsTabViewModel: ObservableObject {
    @Published var entries: [TranscriptEntry] = []
    @Published var searchText: String = ""

    private let reader: any TranscriptReading
    private let clock: @MainActor () -> Date
    private let calendar: Calendar
    private let explicitDateFormatter: DateFormatter

    init(
        reader: any TranscriptReading,
        clock: @escaping @MainActor () -> Date = { Date() },
        calendar: Calendar = .autoupdatingCurrent,
        locale: Locale = Locale(identifier: "en_US_POSIX")
    ) {
        self.reader = reader
        self.clock = clock
        self.calendar = calendar

        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = locale
        // Fixed format produces a stable, locale-independent bucket
        // label ("APRIL 17, 2026") that matches the §3B spec.
        formatter.dateFormat = "MMMM d, yyyy"
        self.explicitDateFormatter = formatter
    }

    /// Load the most-recent `limit` entries from the reader. Default 100
    /// matches §3B guidance for the Transcriptions tab surface.
    func load(limit: Int = 100) async {
        entries = await reader.recent(limit: limit)
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
    /// * Older → uppercased `"MMMM d, yyyy"` (e.g. `"APRIL 17, 2026"`)
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
}
