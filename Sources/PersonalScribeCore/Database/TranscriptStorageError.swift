import Foundation

/// Errors surfaced by `AppDatabase` initialization and write paths. Read paths
/// are non-throwing by policy (plan §3 "Read-error posture: non-throwing") —
/// they log and return empty results rather than throw these cases.
///
/// Cases match the API sketch in `plans/storage-database-layer.md` §3.
public enum TranscriptStorageError: Error, Sendable {
    case openFailed(underlying: Error)
    case runtimeUnsupported(RuntimeGateFailure)
    case migrationFailed(version: String, underlying: Error)
    case decodingFailed(underlying: Error)
    case queryFailed(underlying: Error)
}
