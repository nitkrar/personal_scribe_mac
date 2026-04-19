import Foundation
import XCTest
@testable import SeshatCore

final class DiskSpaceSnapshotTests: XCTestCase {
    private let fileManager = FileManager.default

    func testCaptureReportsManagedDirectoryUsageAndTotal() throws {
        let baseDirectory = try makeTemporaryDirectory()
        defer {
            cleanup(baseDirectory)
        }

        let modelsDirectory = baseDirectory.appendingPathComponent("models", isDirectory: true)
        let recordingsDirectory = baseDirectory.appendingPathComponent("recordings", isDirectory: true)
        let nestedModelDirectory = modelsDirectory.appendingPathComponent("whisper-large-v3", isDirectory: true)
        try fileManager.createDirectory(at: nestedModelDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: recordingsDirectory, withIntermediateDirectories: true)

        try Data(repeating: 0xAA, count: 7).write(
            to: nestedModelDirectory.appendingPathComponent("weights.bin", isDirectory: false)
        )
        try Data(repeating: 0xBB, count: 11).write(
            to: recordingsDirectory.appendingPathComponent("clip.wav", isDirectory: false)
        )

        let capturedAt = Date(timeIntervalSince1970: 1_713_484_800)
        let snapshot = try DiskSpaceSnapshot.capture(
            from: FixedStorageLocator(baseDirectory: baseDirectory),
            fileManager: fileManager,
            capturedAt: capturedAt
        )

        XCTAssertEqual(snapshot.capturedAt, capturedAt)
        XCTAssertEqual(snapshot.baseDirectory, baseDirectory.standardizedFileURL)
        XCTAssertEqual(Set(snapshot.usedBytesByDirectory.keys), Set(ManagedDirectory.allCases))
        XCTAssertGreaterThanOrEqual(snapshot.usedBytesByDirectory[.models] ?? Int64(-1), Int64(7))
        XCTAssertEqual(snapshot.usedBytesByDirectory[.modes], Int64(0))
        XCTAssertGreaterThanOrEqual(snapshot.usedBytesByDirectory[.recordings] ?? Int64(-1), Int64(11))
        XCTAssertEqual(snapshot.usedBytesByDirectory[.logs], Int64(0))
        XCTAssertEqual(snapshot.usedBytesByDirectory[.cache], Int64(0))
        XCTAssertEqual(snapshot.totalUsedBytes, snapshot.usedBytesByDirectory.values.reduce(0, +))

        if let volumeAvailableBytes = snapshot.volumeAvailableBytes {
            XCTAssertGreaterThan(volumeAvailableBytes, 0)
        }
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        return url.standardizedFileURL
    }

    private func cleanup(_ url: URL) {
        try? fileManager.removeItem(at: url)
    }
}
