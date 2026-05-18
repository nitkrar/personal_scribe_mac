import Foundation
import XCTest
@testable import PersonalScribeCore

@MainActor
final class DiagnosticsLogMaintenanceTests: XCTestCase {
    private final class Recorder<Value>: @unchecked Sendable {
        private(set) var values: [Value] = []

        func append(_ value: Value) {
            values.append(value)
        }
    }

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
        let futureLog = logsDirectory.appendingPathComponent("future.log")
        try "errors-yesterday\n".write(to: errorsLog, atomically: true, encoding: .utf8)
        try "diagnostics-yesterday\n".write(to: diagnosticsLog, atomically: true, encoding: .utf8)
        try "future-yesterday\n".write(to: futureLog, atomically: true, encoding: .utf8)
        try setModificationDate(yesterday, for: [errorsLog, diagnosticsLog, futureLog])

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
        XCTAssertEqual(
            try String(contentsOf: logsDirectory.appendingPathComponent("future.log.2026-05-17"), encoding: .utf8),
            "future-yesterday\n"
        )
        XCTAssertEqual(try String(contentsOf: errorsLog, encoding: .utf8), "")
        XCTAssertEqual(try String(contentsOf: diagnosticsLog, encoding: .utf8), "")
        XCTAssertEqual(try String(contentsOf: futureLog, encoding: .utf8), "")
    }

    func testPerformMaintenanceLeavesCurrentDayLogsInPlace() throws {
        let tempDirectory = try makeTemporaryDirectory()
        let locator = FixedStorageLocator(baseDirectory: tempDirectory)
        let logsDirectory = locator.url(for: .logs)
        try FileManager.default.createDirectory(at: logsDirectory, withIntermediateDirectories: true)
        let calendar = fixedCalendar()
        let now = date("2026-05-18T12:00:00Z")
        let currentLog = logsDirectory.appendingPathComponent("errors.log")
        try "still-current\n".write(to: currentLog, atomically: true, encoding: .utf8)
        try setModificationDate(date("2026-05-18T08:30:00Z"), for: [currentLog])

        let service = DiagnosticsLogMaintenanceService(
            storageLocatorProvider: { locator },
            retentionDaysProvider: { 14 },
            calendar: calendar,
            fileManager: FileManager.default,
            atomicFileWriter: FileManagerAtomicFileWriter(fileManager: FileManager.default)
        )

        service.performMaintenance(now: now)

        XCTAssertEqual(try String(contentsOf: currentLog, encoding: .utf8), "still-current\n")
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: logsDirectory.appendingPathComponent("errors.log.2026-05-18").path
            )
        )
    }

    func testPerformMaintenancePrunesArchivesPerBaseNameUsingRetentionDays() throws {
        let tempDirectory = try makeTemporaryDirectory()
        let locator = FixedStorageLocator(baseDirectory: tempDirectory)
        let logsDirectory = locator.url(for: .logs)
        try FileManager.default.createDirectory(at: logsDirectory, withIntermediateDirectories: true)
        let calendar = fixedCalendar()

        for day in 1...5 {
            try "errors-\(day)\n".write(
                to: logsDirectory.appendingPathComponent("errors.log.2026-05-0\(day)"),
                atomically: true,
                encoding: .utf8
            )
        }
        for day in 1...4 {
            try "diagnostics-\(day)\n".write(
                to: logsDirectory.appendingPathComponent("diagnostics.log.2026-05-0\(day)"),
                atomically: true,
                encoding: .utf8
            )
        }

        let service = DiagnosticsLogMaintenanceService(
            storageLocatorProvider: { locator },
            retentionDaysProvider: { 2 },
            calendar: calendar,
            fileManager: FileManager.default,
            atomicFileWriter: FileManagerAtomicFileWriter(fileManager: FileManager.default)
        )

        service.performMaintenance(now: date("2026-05-18T12:00:00Z"))

        XCTAssertEqual(
            try archivedFileNames(in: logsDirectory, prefix: "errors.log."),
            ["errors.log.2026-05-04", "errors.log.2026-05-05"]
        )
        XCTAssertEqual(
            try archivedFileNames(in: logsDirectory, prefix: "diagnostics.log."),
            ["diagnostics.log.2026-05-03", "diagnostics.log.2026-05-04"]
        )
    }

    func testPerformMaintenanceKeepsAllArchivesWhenRetentionDisabled() throws {
        let tempDirectory = try makeTemporaryDirectory()
        let locator = FixedStorageLocator(baseDirectory: tempDirectory)
        let logsDirectory = locator.url(for: .logs)
        try FileManager.default.createDirectory(at: logsDirectory, withIntermediateDirectories: true)
        let calendar = fixedCalendar()

        for day in 1...3 {
            try "errors-\(day)\n".write(
                to: logsDirectory.appendingPathComponent("errors.log.2026-05-0\(day)"),
                atomically: true,
                encoding: .utf8
            )
        }

        let service = DiagnosticsLogMaintenanceService(
            storageLocatorProvider: { locator },
            retentionDaysProvider: { 0 },
            calendar: calendar,
            fileManager: FileManager.default,
            atomicFileWriter: FileManagerAtomicFileWriter(fileManager: FileManager.default)
        )

        service.performMaintenance(now: date("2026-05-18T12:00:00Z"))

        XCTAssertEqual(
            try archivedFileNames(in: logsDirectory, prefix: "errors.log."),
            ["errors.log.2026-05-01", "errors.log.2026-05-02", "errors.log.2026-05-03"]
        )
    }

    func testControllerRunsMaintenanceImmediatelyAndSleepsUntilNextLocalMidnight() async {
        let calendar = fixedCalendar()
        let now = date("2026-05-18T21:15:30Z")
        let maintenanceRuns = Recorder<Date>()
        let sleptDurations = Recorder<Duration>()
        let sleepExpectation = expectation(description: "sleep until midnight")

        let controller = DiagnosticsLogMaintenanceController(
            now: { now },
            calendar: calendar,
            performMaintenance: { maintenanceRuns.append($0) },
            sleep: { duration in
                sleptDurations.append(duration)
                sleepExpectation.fulfill()
                throw CancellationError()
            }
        )

        controller.start()
        await fulfillment(of: [sleepExpectation], timeout: 1.0)

        XCTAssertEqual(maintenanceRuns.values, [now])
        XCTAssertEqual(
            sleptDurations.values,
            [.nanoseconds(9_870_000_000_000)]
        )
    }

    func testControllerStartIsIdempotent() async {
        let calendar = fixedCalendar()
        let now = date("2026-05-18T21:15:30Z")
        let maintenanceRuns = Recorder<Date>()
        let sleepExpectation = expectation(description: "single sleep only")
        sleepExpectation.expectedFulfillmentCount = 1

        let controller = DiagnosticsLogMaintenanceController(
            now: { now },
            calendar: calendar,
            performMaintenance: { maintenanceRuns.append($0) },
            sleep: { _ in
                sleepExpectation.fulfill()
                throw CancellationError()
            }
        )

        controller.start()
        controller.start()
        await fulfillment(of: [sleepExpectation], timeout: 1.0)

        XCTAssertEqual(maintenanceRuns.values, [now])
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

    private func archivedFileNames(in directory: URL, prefix: String) throws -> [String] {
        try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )
        .map(\.lastPathComponent)
        .filter { $0.hasPrefix(prefix) }
        .sorted()
    }
}
