import Foundation

/// Ordering clause for `TranscriptRepository.entries(in:orderedBy:)`. The two
/// cases map directly onto `ORDER BY timestamp ASC` / `DESC` in the generated
/// SQL. Defined outside `TranscriptRepository` so call sites can spell the
/// value as `TranscriptOrder.timestampAscending` rather than a nested type.
///
/// Per plan §3 API sketch (plans/storage-database-layer.md §3). No default
/// ordering is provided: callers pick explicitly, since "newest first" vs
/// "oldest first" differ across window-based use cases.
public enum TranscriptOrder: Sendable {
    case timestampAscending
    case timestampDescending
}
