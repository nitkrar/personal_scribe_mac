import Foundation

/// Failure modes surfaced by `AppDatabase` runtime pre-checks (SQLite version,
/// FTS5 compile option, FTS tokenizer configuration). 1:1 re-home of the
/// `OpenError` cases that lived on `SQLiteTranscriptStore`; the storage-layer
/// refactor (plan `plans/storage-database-layer.md`, backlog #026) moves them
/// here so `AppDatabase` can wrap them inside `TranscriptStorageError`.
public enum RuntimeGateFailure: Sendable, Equatable {
    case unsupportedSQLiteVersion(current: String, minimum: String)
    case missingFTS5CompileOption
    case invalidFTSTokenizerConfiguration(sql: String?)
}
