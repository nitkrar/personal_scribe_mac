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
}
