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
            try String(contentsOf: logsDirectory.appendingPathComponent("errors.log.2026-05-17"), encoding: .utf8),
            "errors-yesterday\n"
        )
        XCTAssertEqual(
            try String(contentsOf: logsDirectory.appendingPathComponent("diagnostics.log.2026-05-17"), encoding: .utf8),
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
            to: logsDirectory.appendingPathComponent("errors.log.2026-05-15"),
            atomically: true,
            encoding: .utf8
        )
        try "older-errors-2\n".write(
            to: logsDirectory.appendingPathComponent("errors.log.2026-05-16"),
            atomically: true,
            encoding: .utf8
        )
        try setModificationDate(yesterday, for: [currentLog])

        makeService(locator: locator, retentionDays: 2).performMaintenance(now: now)

        XCTAssertEqual(existingArchiveNames(for: "errors.log", in: logsDirectory), [
            "errors.log.2026-05-16",
            "errors.log.2026-05-17",
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
            to: logsDirectory.appendingPathComponent("diagnostics.log.2026-05-15"),
            atomically: true,
            encoding: .utf8
        )
        try "older-diagnostics-2\n".write(
            to: logsDirectory.appendingPathComponent("diagnostics.log.2026-05-16"),
            atomically: true,
            encoding: .utf8
        )
        try setModificationDate(yesterday, for: [currentLog])

        makeService(locator: locator, retentionDays: 2).performMaintenance(now: now)

        XCTAssertEqual(existingArchiveNames(for: "diagnostics.log", in: logsDirectory), [
            "diagnostics.log.2026-05-16",
            "diagnostics.log.2026-05-17",
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
            to: logsDirectory.appendingPathComponent("debug.log.2026-05-14"),
            atomically: true,
            encoding: .utf8
        )
        try "older-debug-2\n".write(
            to: logsDirectory.appendingPathComponent("debug.log.2026-05-15"),
            atomically: true,
            encoding: .utf8
        )
        try "older-debug-3\n".write(
            to: logsDirectory.appendingPathComponent("debug.log.2026-05-16"),
            atomically: true,
            encoding: .utf8
        )
        try setModificationDate(yesterday, for: [currentLog])

        makeService(locator: locator, retentionDays: 90).performMaintenance(now: now)

        XCTAssertEqual(existingArchiveNames(for: "debug.log", in: logsDirectory), [
            "debug.log.2026-05-15",
            "debug.log.2026-05-16",
            "debug.log.2026-05-17",
        ])
        XCTAssertEqual(try String(contentsOf: currentLog, encoding: .utf8), "")
    }

    func testPerformMaintenanceDeletesArchivedDebugLogsBeyondThreeDays() throws {
        let tempDirectory = try makeTemporaryDirectory()
        let locator = FixedStorageLocator(baseDirectory: tempDirectory)
        let logsDirectory = locator.url(for: .logs)
        try FileManager.default.createDirectory(at: logsDirectory, withIntermediateDirectories: true)

        try "debug-1\n".write(
            to: logsDirectory.appendingPathComponent("debug.log.2026-05-12"),
            atomically: true,
            encoding: .utf8
        )
        try "debug-2\n".write(
            to: logsDirectory.appendingPathComponent("debug.log.2026-05-13"),
            atomically: true,
            encoding: .utf8
        )
        try "debug-3\n".write(
            to: logsDirectory.appendingPathComponent("debug.log.2026-05-14"),
            atomically: true,
            encoding: .utf8
        )
        try "debug-4\n".write(
            to: logsDirectory.appendingPathComponent("debug.log.2026-05-15"),
            atomically: true,
            encoding: .utf8
        )
        try "errors-1\n".write(
            to: logsDirectory.appendingPathComponent("errors.log.2026-05-12"),
            atomically: true,
            encoding: .utf8
        )
        try "errors-2\n".write(
            to: logsDirectory.appendingPathComponent("errors.log.2026-05-13"),
            atomically: true,
            encoding: .utf8
        )

        makeService(locator: locator, retentionDays: 0).performMaintenance(now: date("2026-05-18T12:00:00Z"))

        XCTAssertEqual(existingArchiveNames(for: "debug.log", in: logsDirectory), [
            "debug.log.2026-05-13",
            "debug.log.2026-05-14",
            "debug.log.2026-05-15",
        ])
        XCTAssertEqual(existingArchiveNames(for: "errors.log", in: logsDirectory), [
            "errors.log.2026-05-12",
            "errors.log.2026-05-13",
        ])
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
        let prefix = "\(baseLogName)."
        let fileNames = (try? FileManager.default.contentsOfDirectory(atPath: logsDirectory.path)) ?? []
        return fileNames
            .filter { $0.hasPrefix(prefix) }
            .sorted()
    }
}
