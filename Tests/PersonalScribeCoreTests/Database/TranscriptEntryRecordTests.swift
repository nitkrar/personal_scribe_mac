import Foundation
import GRDB
import XCTest
@testable import PersonalScribeCore

/// Roundtrip + edge-case coverage for `TranscriptEntry`'s GRDB
/// `FetchableRecord` + `PersistableRecord` conformance (step 1.3).
/// Schema DDL reproduced inline from `v1_transcripts_table` so this test
/// does not depend on any future migrator surface.
final class TranscriptEntryRecordTests: XCTestCase {
    private func makeInMemoryQueue() throws -> DatabaseQueue {
        let dbQueue = try DatabaseQueue(path: ":memory:")
        try dbQueue.write { db in
            try db.execute(sql: """
                CREATE TABLE transcripts (
                    id TEXT PRIMARY KEY NOT NULL,
                    timestamp REAL NOT NULL,
                    text TEXT NOT NULL,
                    audio_duration REAL NOT NULL,
                    processing_duration REAL NOT NULL
                )
                """)
        }
        return dbQueue
    }

    func testRoundTripInsertAndFetch() throws {
        let dbQueue = try makeInMemoryQueue()
        let entry = TranscriptEntry(
            id: UUID(),
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            text: "hello world",
            audioDuration: 1.5,
            processingDuration: 0.25
        )

        try dbQueue.write { db in
            try entry.insert(db)
        }

        let fetched = try dbQueue.read { db in
            try TranscriptEntry.fetchAll(db, sql: "SELECT * FROM transcripts")
        }

        XCTAssertEqual(fetched, [entry])
    }

    func testInvalidUUIDDecodeThrows() throws {
        let dbQueue = try makeInMemoryQueue()
        try dbQueue.write { db in
            try db.execute(
                sql: """
                INSERT INTO transcripts (
                    id, timestamp, text, audio_duration, processing_duration
                ) VALUES (?, ?, ?, ?, ?)
                """,
                arguments: ["not-a-uuid", 1.0, "oops", 0.0, 0.0]
            )
        }

        XCTAssertThrowsError(
            try dbQueue.read { db in
                try TranscriptEntry.fetchAll(db, sql: "SELECT * FROM transcripts")
            }
        ) { error in
            // The underlying error must be a `DecodingError.dataCorrupted`
            // whose message mentions the invalid identifier so callers can
            // surface a meaningful failure.
            guard case DecodingError.dataCorrupted(let context) = error else {
                XCTFail("Expected DecodingError.dataCorrupted, got \(error)")
                return
            }
            XCTAssertTrue(
                context.debugDescription.contains("not-a-uuid"),
                "Debug description should mention the invalid UUID; got: \(context.debugDescription)"
            )
        }
    }

    func testTimestampRoundTripPrecision() throws {
        let dbQueue = try makeInMemoryQueue()
        let timestamp = Date(timeIntervalSince1970: 123.456)
        let entry = TranscriptEntry(
            id: UUID(),
            timestamp: timestamp,
            text: "ts",
            audioDuration: 0.0,
            processingDuration: 0.0
        )

        try dbQueue.write { db in
            try entry.insert(db)
        }

        let fetched = try dbQueue.read { db in
            try TranscriptEntry.fetchAll(db, sql: "SELECT * FROM transcripts")
        }

        XCTAssertEqual(fetched.count, 1)
        let roundTripped = try XCTUnwrap(fetched.first)
        XCTAssertEqual(
            roundTripped.timestamp.timeIntervalSince1970,
            timestamp.timeIntervalSince1970,
            accuracy: 0.001
        )
    }
}
