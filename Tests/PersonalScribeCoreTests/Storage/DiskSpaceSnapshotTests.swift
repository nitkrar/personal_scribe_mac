import Foundation
import XCTest
@testable import PersonalScribeCore

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
        let expectedVolumeAvailableBytes = try baseDirectory.resourceValues(
            forKeys: [.volumeAvailableCapacityForImportantUsageKey]
        ).volumeAvailableCapacityForImportantUsage
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

        assertVolumeAvailableBytes(
            snapshot.volumeAvailableBytes,
            closeTo: expectedVolumeAvailableBytes
        )
    }

    func testCaptureTreatsMissingBaseDirectoryAsEmptySnapshotWithoutCreatingDirectories() throws {
        let existingParentDirectory = try makeTemporaryDirectory()
        defer {
            cleanup(existingParentDirectory)
        }

        let missingBaseDirectory = existingParentDirectory
            .appendingPathComponent("missing-base", isDirectory: true)
            .standardizedFileURL
        let expectedVolumeAvailableBytes = try existingParentDirectory.resourceValues(
            forKeys: [.volumeAvailableCapacityForImportantUsageKey]
        ).volumeAvailableCapacityForImportantUsage

        let snapshot = try DiskSpaceSnapshot.capture(
            from: FixedStorageLocator(baseDirectory: missingBaseDirectory),
            fileManager: fileManager,
            capturedAt: Date(timeIntervalSince1970: 1_713_571_200)
        )

        XCTAssertFalse(fileManager.fileExists(atPath: missingBaseDirectory.path))
        XCTAssertEqual(snapshot.baseDirectory, missingBaseDirectory)
        XCTAssertEqual(Set(snapshot.usedBytesByDirectory.keys), Set(ManagedDirectory.allCases))
        XCTAssertTrue(snapshot.usedBytesByDirectory.values.allSatisfy { $0 == 0 })
        XCTAssertEqual(snapshot.totalUsedBytes, 0)
        assertVolumeAvailableBytes(
            snapshot.volumeAvailableBytes,
            closeTo: expectedVolumeAvailableBytes
        )
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        return url.standardizedFileURL
    }

    private func cleanup(_ url: URL) {
        try? fileManager.removeItem(at: url)
    }

    /// Asserts that two system-wide volume-available-byte counts are within a
    /// tolerance of each other. The test takes two independent readings of
    /// `.volumeAvailableCapacityForImportantUsage` (one via `resourceValues`,
    /// one via `DiskSpaceSnapshot.capture`) and the OS is free to write
    /// between them, so exact equality is a race. Tolerance = 50 MiB, which
    /// is generous enough to absorb concurrent logging / indexing traffic
    /// while still catching order-of-magnitude regressions.
    private func assertVolumeAvailableBytes(
        _ actual: Int64?,
        closeTo expected: Int64?,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let tolerance: Int64 = 50 * 1024 * 1024
        switch (actual, expected) {
        case let (lhs?, rhs?):
            let delta = abs(lhs - rhs)
            XCTAssertLessThanOrEqual(
                delta,
                tolerance,
                "volumeAvailableBytes drifted by \(delta) bytes between the "
                    + "pre-capture reading (\(rhs)) and the snapshot reading "
                    + "(\(lhs)); tolerance is \(tolerance) bytes.",
                file: file,
                line: line
            )
        case (nil, nil):
            break
        case (nil, _?), (_?, nil):
            XCTFail(
                "volumeAvailableBytes nil-ness mismatch: expected \(String(describing: expected)), got \(String(describing: actual))",
                file: file,
                line: line
            )
        }
    }
}
