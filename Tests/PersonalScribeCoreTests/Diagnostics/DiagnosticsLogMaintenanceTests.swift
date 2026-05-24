import Foundation
import XCTest
@testable import PersonalScribeCore

@MainActor
final class DiagnosticsLogMaintenanceTests: XCTestCase {
    func testPerformMaintenanceRotatesStaleCurrentLogsAndCreatesFreshEmptyFiles() throws {
        let tempDirectory = try makeTemporaryDirectory()
        let locator = FixedStorageLocator(baseDirectory: tempDirectory)
        let logsDirectory = locator.url(for: .logs)
        try FileManager.default.createDirectory(at: logsDirectory, withIntermediateDirectories: true)
        let calendar = fixedCalendar()
        let now = date("2026-05-18T12:00:00Z")
        let yesterday = date("2026-05-17T20:30:00Z")

        let errorsLog = logsDirectory.appendingPathComponent("errors.log")
        let diagnosticsLog = logsDirectory.appendingPathComponent("diagnostics.log")
        try "errors-yesterday\n".write(to: errorsLog, atomically: true, encoding: .utf8)
        try "diagnostics-yesterday\n".write(to: diagnosticsLog, atomically: true, encoding: .utf8)
        try setModificationDate(yesterday, for: [errorsLog, diagnosticsLog])

        let service = DiagnosticsLogMaintenanceService(
            storageLocatorProvider: { locator },
            retentionDaysProvider: { 14 },
            calendar: calendar,
            fileManager: FileManager.default,
            atomicFileWriter: FileManagerAtomicFileWriter(fileManager: FileManager.default)
        )

        service.performMaintenance(now: now)

        XCTAssertEqual(
            try String(contentsOf: logsDirectory.appendingPathComponent("errors.2026-05-17.log"), encoding: .utf8),
            "errors-yesterday\n"
        )
        XCTAssertEqual(
            try String(contentsOf: logsDirectory.appendingPathComponent("diagnostics.2026-05-17.log"), encoding: .utf8),
            "diagnostics-yesterday\n"
        )
        XCTAssertEqual(try String(contentsOf: errorsLog, encoding: .utf8), "")
        XCTAssertEqual(try String(contentsOf: diagnosticsLog, encoding: .utf8), "")
    }

    func testPerformMaintenanceRotatesErrorsLogPerPreference() throws {
        let tempDirectory = try makeTemporaryDirectory()
        let locator = FixedStorageLocator(baseDirectory: tempDirectory)
        let logsDirectory = locator.url(for: .logs)
        try FileManager.default.createDirectory(at: logsDirectory, withIntermediateDirectories: true)
        let now = date("2026-05-18T12:00:00Z")
        let yesterday = date("2026-05-17T20:30:00Z")
        let currentLog = logsDirectory.appendingPathComponent("errors.log")

        try "current-errors\n".write(to: currentLog, atomically: true, encoding: .utf8)
        try "older-errors-1\n".write(
            to: logsDirectory.appendingPathComponent("errors.2026-05-15.log"),
            atomically: true,
            encoding: .utf8
        )
        try "older-errors-2\n".write(
            to: logsDirectory.appendingPathComponent("errors.2026-05-16.log"),
            atomically: true,
            encoding: .utf8
        )
        try setModificationDate(yesterday, for: [currentLog])

        makeService(locator: locator, retentionDays: 2).performMaintenance(now: now)

        XCTAssertEqual(existingArchiveNames(for: "errors.log", in: logsDirectory), [
            "errors.2026-05-16.log",
            "errors.2026-05-17.log",
        ])
        XCTAssertEqual(try String(contentsOf: currentLog, encoding: .utf8), "")
    }

    func testPerformMaintenanceRotatesDiagnosticsLogPerPreference() throws {
        let tempDirectory = try makeTemporaryDirectory()
        let locator = FixedStorageLocator(baseDirectory: tempDirectory)
        let logsDirectory = locator.url(for: .logs)
        try FileManager.default.createDirectory(at: logsDirectory, withIntermediateDirectories: true)
        let now = date("2026-05-18T12:00:00Z")
        let yesterday = date("2026-05-17T20:30:00Z")
        let currentLog = logsDirectory.appendingPathComponent("diagnostics.log")

        try "current-diagnostics\n".write(to: currentLog, atomically: true, encoding: .utf8)
        try "older-diagnostics-1\n".write(
            to: logsDirectory.appendingPathComponent("diagnostics.2026-05-15.log"),
            atomically: true,
            encoding: .utf8
        )
        try "older-diagnostics-2\n".write(
            to: logsDirectory.appendingPathComponent("diagnostics.2026-05-16.log"),
            atomically: true,
            encoding: .utf8
        )
        try setModificationDate(yesterday, for: [currentLog])

        makeService(locator: locator, retentionDays: 2).performMaintenance(now: now)

        XCTAssertEqual(existingArchiveNames(for: "diagnostics.log", in: logsDirectory), [
            "diagnostics.2026-05-16.log",
            "diagnostics.2026-05-17.log",
        ])
        XCTAssertEqual(try String(contentsOf: currentLog, encoding: .utf8), "")
    }

    func testPerformMaintenanceRotatesDebugLogAtThreeDaysRegardlessOfPreference() throws {
        let tempDirectory = try makeTemporaryDirectory()
        let locator = FixedStorageLocator(baseDirectory: tempDirectory)
        let logsDirectory = locator.url(for: .logs)
        try FileManager.default.createDirectory(at: logsDirectory, withIntermediateDirectories: true)
        let now = date("2026-05-18T12:00:00Z")
        let yesterday = date("2026-05-17T20:30:00Z")
        let currentLog = logsDirectory.appendingPathComponent("debug.log")

        try "current-debug\n".write(to: currentLog, atomically: true, encoding: .utf8)
        try "older-debug-1\n".write(
            to: logsDirectory.appendingPathComponent("debug.2026-05-14.log"),
            atomically: true,
            encoding: .utf8
        )
        try "older-debug-2\n".write(
            to: logsDirectory.appendingPathComponent("debug.2026-05-15.log"),
            atomically: true,
            encoding: .utf8
        )
        try "older-debug-3\n".write(
            to: logsDirectory.appendingPathComponent("debug.2026-05-16.log"),
            atomically: true,
            encoding: .utf8
        )
        try setModificationDate(yesterday, for: [currentLog])

        makeService(locator: locator, retentionDays: 90).performMaintenance(now: now)

        XCTAssertEqual(existingArchiveNames(for: "debug.log", in: logsDirectory), [
            "debug.2026-05-15.log",
            "debug.2026-05-16.log",
            "debug.2026-05-17.log",
        ])
        XCTAssertEqual(try String(contentsOf: currentLog, encoding: .utf8), "")
    }

    func testPerformMaintenanceDeletesArchivedDebugLogsBeyondThreeDays() throws {
        let tempDirectory = try makeTemporaryDirectory()
        let locator = FixedStorageLocator(baseDirectory: tempDirectory)
        let logsDirectory = locator.url(for: .logs)
        try FileManager.default.createDirectory(at: logsDirectory, withIntermediateDirectories: true)

        try "debug-1\n".write(
            to: logsDirectory.appendingPathComponent("debug.2026-05-12.log"),
            atomically: true,
            encoding: .utf8
        )
        try "debug-2\n".write(
            to: logsDirectory.appendingPathComponent("debug.2026-05-13.log"),
            atomically: true,
            encoding: .utf8
        )
        try "debug-3\n".write(
            to: logsDirectory.appendingPathComponent("debug.2026-05-14.log"),
            atomically: true,
            encoding: .utf8
        )
        try "debug-4\n".write(
            to: logsDirectory.appendingPathComponent("debug.2026-05-15.log"),
            atomically: true,
            encoding: .utf8
        )
        try "errors-1\n".write(
            to: logsDirectory.appendingPathComponent("errors.2026-05-12.log"),
            atomically: true,
            encoding: .utf8
        )
        try "errors-2\n".write(
            to: logsDirectory.appendingPathComponent("errors.2026-05-13.log"),
            atomically: true,
            encoding: .utf8
        )

        makeService(locator: locator, retentionDays: 0).performMaintenance(now: date("2026-05-18T12:00:00Z"))

        XCTAssertEqual(existingArchiveNames(for: "debug.log", in: logsDirectory), [
            "debug.2026-05-13.log",
            "debug.2026-05-14.log",
            "debug.2026-05-15.log",
        ])
        XCTAssertEqual(existingArchiveNames(for: "errors.log", in: logsDirectory), [
            "errors.2026-05-12.log",
            "errors.2026-05-13.log",
        ])
    }

    func testPerformMaintenanceMigratesLegacyDotLogDotDateArchivesToNewShape() throws {
        // Pre-2026-05-24 archives used `<base>.log.<YYYY-MM-DD>` (no .log
        // suffix on the rotated file). On first run the maintenance pass
        // renames them in place to `<base>.<YYYY-MM-DD>.log` so the rest
        // of the pipeline can assume the new shape. After migration the
        // pruner applies retention against the renamed files.
        let tempDirectory = try makeTemporaryDirectory()
        let locator = FixedStorageLocator(baseDirectory: tempDirectory)
        let logsDirectory = locator.url(for: .logs)
        try FileManager.default.createDirectory(at: logsDirectory, withIntermediateDirectories: true)
        let now = date("2026-05-18T12:00:00Z")
        let currentLog = logsDirectory.appendingPathComponent("errors.log")
        try "current\n".write(to: currentLog, atomically: true, encoding: .utf8)
        try "old-12\n".write(
            to: logsDirectory.appendingPathComponent("errors.log.2026-05-12"),
            atomically: true,
            encoding: .utf8
        )
        try "old-13\n".write(
            to: logsDirectory.appendingPathComponent("errors.log.2026-05-13"),
            atomically: true,
            encoding: .utf8
        )
        try "old-15\n".write(
            to: logsDirectory.appendingPathComponent("errors.log.2026-05-15"),
            atomically: true,
            encoding: .utf8
        )

        makeService(locator: locator, retentionDays: 2).performMaintenance(now: now)

        let remaining = (try FileManager.default.contentsOfDirectory(atPath: logsDirectory.path)).sorted()
        // Legacy shape gone entirely after migration.
        XCTAssertFalse(remaining.contains("errors.log.2026-05-12"), "Legacy filename should be migrated away. Remaining: \(remaining)")
        XCTAssertFalse(remaining.contains("errors.log.2026-05-13"), "Legacy filename should be migrated away. Remaining: \(remaining)")
        XCTAssertFalse(remaining.contains("errors.log.2026-05-15"), "Legacy filename should be migrated away. Remaining: \(remaining)")
        // Oldest archive pruned per retentionDays=2; 2 newest survived in new shape.
        XCTAssertFalse(remaining.contains("errors.2026-05-12.log"), "Oldest archive should be pruned post-migration. Remaining: \(remaining)")
        XCTAssertTrue(remaining.contains("errors.2026-05-13.log"), "Second-newest archive should survive in new shape. Remaining: \(remaining)")
        XCTAssertTrue(remaining.contains("errors.2026-05-15.log"), "Newest archive should survive in new shape. Remaining: \(remaining)")
    }

    func testMigrationDropsLegacyArchiveWhenNewShapeAlreadyExists() throws {
        // If a previous maintenance run already wrote the new-shape
        // archive (e.g. partial migration after a crash), the legacy
        // duplicate is removed rather than overwriting the new file.
        let tempDirectory = try makeTemporaryDirectory()
        let locator = FixedStorageLocator(baseDirectory: tempDirectory)
        let logsDirectory = locator.url(for: .logs)
        try FileManager.default.createDirectory(at: logsDirectory, withIntermediateDirectories: true)
        let now = date("2026-05-18T12:00:00Z")
        try "current\n".write(to: logsDirectory.appendingPathComponent("errors.log"), atomically: true, encoding: .utf8)
        try "legacy-contents\n".write(
            to: logsDirectory.appendingPathComponent("errors.log.2026-05-17"),
            atomically: true,
            encoding: .utf8
        )
        try "canonical-contents\n".write(
            to: logsDirectory.appendingPathComponent("errors.2026-05-17.log"),
            atomically: true,
            encoding: .utf8
        )

        makeService(locator: locator, retentionDays: 7).performMaintenance(now: now)

        let remaining = (try FileManager.default.contentsOfDirectory(atPath: logsDirectory.path)).sorted()
        XCTAssertFalse(remaining.contains("errors.log.2026-05-17"), "Legacy duplicate should be removed when new-shape file already exists.")
        XCTAssertTrue(remaining.contains("errors.2026-05-17.log"), "Canonical new-shape file should remain untouched.")
        let canonical = try String(contentsOf: logsDirectory.appendingPathComponent("errors.2026-05-17.log"), encoding: .utf8)
        XCTAssertEqual(canonical, "canonical-contents\n", "Canonical file's contents must not be overwritten by the legacy duplicate.")
    }

    private func fixedCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func date(_ iso8601: String) -> Date {
        ISO8601DateFormatter().date(from: iso8601)!
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func setModificationDate(_ date: Date, for urls: [URL]) throws {
        for url in urls {
            try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
        }
    }

    private func makeService(
        locator: FixedStorageLocator,
        retentionDays: Int
    ) -> DiagnosticsLogMaintenanceService {
        DiagnosticsLogMaintenanceService(
            storageLocatorProvider: { locator },
            retentionDaysProvider: { retentionDays },
            calendar: fixedCalendar(),
            fileManager: FileManager.default,
            atomicFileWriter: FileManagerAtomicFileWriter(fileManager: FileManager.default)
        )
    }

    private func existingArchiveNames(for baseLogName: String, in logsDirectory: URL) -> [String] {
        // baseLogName is e.g. "errors.log"; archives are
        // "errors.<YYYY-MM-DD>.log". Filter to that prefix shape and
        // exclude the current `errors.log` itself.
        let stem = baseLogName.hasSuffix(".log")
            ? String(baseLogName.dropLast(4))
            : baseLogName
        let archivePrefix = "\(stem)."
        let fileNames = (try? FileManager.default.contentsOfDirectory(atPath: logsDirectory.path)) ?? []
        return fileNames
            .filter { $0 != baseLogName && $0.hasPrefix(archivePrefix) && $0.hasSuffix(".log") }
            .sorted()
    }
}
