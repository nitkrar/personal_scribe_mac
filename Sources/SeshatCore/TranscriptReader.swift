import Foundation

public protocol TranscriptReading: Sendable {
    func recent(limit: Int) async -> [TranscriptEntry]
    func search(query: String) async -> [TranscriptEntry]
    func all() async -> [TranscriptEntry]
}

public struct SQLiteTranscriptReader: TranscriptReading, Sendable {
    private let store: SQLiteTranscriptStore
    private let logger: SeshatLogger

    public init(
        store: SQLiteTranscriptStore,
        logger: SeshatLogger = SeshatLogger(category: SeshatLogCategory.app)
    ) {
        self.store = store
        self.logger = logger
    }

    public func recent(limit: Int) async -> [TranscriptEntry] {
        await store.recent(limit: limit)
    }

    public func search(query: String) async -> [TranscriptEntry] {
        do {
            return try await store.search(query: query)
        } catch {
            logger.error("Failed to search SQLite transcripts through TranscriptReading adapter", error: error)
            return []
        }
    }

    public func all() async -> [TranscriptEntry] {
        let count = await store.count()
        guard count > 0 else {
            return []
        }

        return await store.recent(limit: count)
    }
}
