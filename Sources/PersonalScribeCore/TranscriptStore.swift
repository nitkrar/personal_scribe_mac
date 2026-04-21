import Foundation
import GRDB

public struct TranscriptEntry: Codable, Sendable, Equatable {
    public let id: UUID
    public let timestamp: Date
    public let text: String
    public let audioDuration: TimeInterval
    public let processingDuration: TimeInterval

    public init(
        id: UUID,
        timestamp: Date,
        text: String,
        audioDuration: TimeInterval,
        processingDuration: TimeInterval
    ) {
        self.id = id
        self.timestamp = timestamp
        self.text = text
        self.audioDuration = audioDuration
        self.processingDuration = processingDuration
    }

    /// Snake_case `CodingKeys` aligned to the `transcripts` SQLite schema
    /// (`audio_duration`, `processing_duration`). Applied to JSON wire format
    /// too — JSONL sidecar is being deleted, so the rename is safe.
    public enum CodingKeys: String, CodingKey {
        case id
        case timestamp
        case text
        case audioDuration = "audio_duration"
        case processingDuration = "processing_duration"
    }
}

// GRDB conformance via `init(row:)` + `encode(to container:)` on the row
// protocols (NOT Codable-delegated). Keeps SQLite's REAL (`timeIntervalSince1970`)
// timestamp and TEXT UUID handling isolated from the JSONL JSON encoder's
// iso8601 Date strategy, and throws `DecodingError.dataCorrupted` on invalid
// UUIDs at the decode boundary.
extension TranscriptEntry: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "transcripts"

    public init(row: Row) throws {
        let rawID: String = row[CodingKeys.id.stringValue]
        guard let uuid = UUID(uuidString: rawID) else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: [CodingKeys.id],
                    debugDescription: "Invalid UUID string: \(rawID)"
                )
            )
        }
        let timestampInterval: TimeInterval = row[CodingKeys.timestamp.stringValue]
        self.init(
            id: uuid,
            timestamp: Date(timeIntervalSince1970: timestampInterval),
            text: row[CodingKeys.text.stringValue],
            audioDuration: row[CodingKeys.audioDuration.stringValue],
            processingDuration: row[CodingKeys.processingDuration.stringValue]
        )
    }

    public func encode(to container: inout PersistenceContainer) throws {
        container[CodingKeys.id.stringValue] = id.uuidString
        container[CodingKeys.timestamp.stringValue] = timestamp.timeIntervalSince1970
        container[CodingKeys.text.stringValue] = text
        container[CodingKeys.audioDuration.stringValue] = audioDuration
        container[CodingKeys.processingDuration.stringValue] = processingDuration
    }
}
