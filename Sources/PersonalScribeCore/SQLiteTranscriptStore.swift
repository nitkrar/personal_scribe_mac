import Foundation
import GRDB

/// Thin forwarding shim over `AppDatabase` + `TranscriptRepository`. Retained
/// only for source-compatibility with test fixtures during the storage-layer
/// refactor (plan `plans/storage-database-layer.md` Pass 2) — production
/// callers construct the repository directly via `AppComposition`.
///
/// Plan §4 Pass 2 is explicit: no shim for legacy data, no sidecar import.
/// A fresh install that somehow has only a JSONL sidecar (never opened a
/// post-Phase-3.D build) starts with an empty history — explicit accepted loss.
public actor SQLiteTranscriptStore {
    private let repository: TranscriptRepository

    public init(recordingsDirectory: URL, ringCapacity: Int = 500) throws {
        let storageLocator = FixedBaseDirectoryStorageLocator(
            baseDirectory: recordingsDirectory.deletingLastPathComponent(),
            managedDirectoryOverrides: [.recordings: recordingsDirectory]
        )
        try self.init(storageLocator: storageLocator, ringCapacity: ringCapacity)
    }

    public init(
        storageLocator: any StorageLocator,
        ringCapacity: Int = 500,
        atomicFileWriter: any AtomicFileWriter = FileManagerAtomicFileWriter()
    ) throws {
        // `ringCapacity` and `atomicFileWriter` are retained for source-compat
        // with pre-Pass-2 call sites; neither is meaningful now (SQLite has no
        // ring buffer, and the JSONL bootstrap has been deleted outright).
        _ = ringCapacity
        _ = atomicFileWriter

        let database = try AppDatabase(locator: storageLocator)
        self.repository = TranscriptRepository(database: database)
    }

    public func append(_ entry: TranscriptEntry) async throws {
        try await repository.append(entry)
    }

    public func recent(limit: Int) async -> [TranscriptEntry] {
        await repository.recent(limit: limit)
    }

    public func count() async -> Int {
        await repository.count()
    }

    public func search(query: String) async throws -> [TranscriptEntry] {
        await repository.search(query: query)
    }
}
