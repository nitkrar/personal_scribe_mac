import Foundation
import os

public struct DiagnosticsLogMaintenanceService: @unchecked Sendable {
    private static let debugLogRetentionDays = 3

    private let storageLocatorProvider: @Sendable () -> any StorageLocator
    private let retentionDaysProvider: @Sendable () -> Int
    private let calendar: Calendar
    private let fileManager: FileManager
    private let atomicFileWriter: any AtomicFileWriter
    private let fallbackLogger: Logger

    public init(
        storageLocatorProvider: @escaping @Sendable () -> any StorageLocator = { AppConfig.liveStorageLocator() },
        retentionDaysProvider: @escaping @Sendable () -> Int = {
            LogRetentionDaysPreference.resolve()
        },
        calendar: Calendar = .autoupdatingCurrent,
        fileManager: FileManager = .default,
        atomicFileWriter: any AtomicFileWriter = FileManagerAtomicFileWriter()
    ) {
        self.storageLocatorProvider = storageLocatorProvider
        self.retentionDaysProvider = retentionDaysProvider
        self.calendar = calendar
        self.fileManager = fileManager
        self.atomicFileWriter = atomicFileWriter
        fallbackLogger = Logger(
            subsystem: AppBrand.logSubsystem,
            category: PersonalScribeLogCategory.app
        )
    }

    public func performMaintenance(now: Date = Date()) {
        do {
            let locator = storageLocatorProvider()
            let logsDirectory = locator.url(for: .logs)
            try locator.ensureDirectoriesExist()
            try fileManager.createDirectory(at: logsDirectory, withIntermediateDirectories: true)

            let currentDayStart = calendar.startOfDay(for: now)
            try rotateStaleCurrentLogs(in: logsDirectory, currentDayStart: currentDayStart)
            try pruneArchivedLogs(in: logsDirectory)
        } catch {
            fallbackLogger.error("Failed to maintain diagnostics logs")
        }
    }

    private func rotateStaleCurrentLogs(
        in logsDirectory: URL,
        currentDayStart: Date
    ) throws {
        for activeLog in try activeLogs(in: logsDirectory) {
            let modificationDayStart = calendar.startOfDay(for: activeLog.modificationDate)
            guard modificationDayStart < currentDayStart else {
                continue
            }

            if activeLog.sizeInBytes > 0 {
                let archiveURL = logsDirectory.appendingPathComponent(
                    "\(activeLog.url.lastPathComponent).\(archiveDateString(for: modificationDayStart))",
                    isDirectory: false
                )
                try archive(activeLog.url, to: archiveURL)
            }

            try touchEmptyLog(at: activeLog.url)
        }
    }

    private func pruneArchivedLogs(in logsDirectory: URL) throws {
        let mainLogRetentionDays = LogRetentionDaysPreference.sanitized(retentionDaysProvider())
        let groupedArchives = Dictionary(grouping: try archivedLogs(in: logsDirectory)) { $0.baseLogName }
        for (baseLogName, archives) in groupedArchives {
            let retentionDays = retentionDays(for: baseLogName, mainLogRetentionDays: mainLogRetentionDays)
            guard retentionDays > 0 else {
                continue
            }

            let sorted = archives.sorted { lhs, rhs in
                if lhs.archiveDate == rhs.archiveDate {
                    return lhs.url.lastPathComponent > rhs.url.lastPathComponent
                }
                return lhs.archiveDate > rhs.archiveDate
            }

            for staleArchive in sorted.dropFirst(retentionDays) {
                try? fileManager.removeItem(at: staleArchive.url)
            }
        }
    }

    private func activeLogs(in logsDirectory: URL) throws -> [ActiveLogFile] {
        try fileManager.contentsOfDirectory(
            at: logsDirectory,
            includingPropertiesForKeys: [
                .contentModificationDateKey,
                .fileSizeKey,
                .isRegularFileKey,
            ],
            options: [.skipsHiddenFiles]
        )
        .compactMap { url -> ActiveLogFile? in
            guard url.lastPathComponent.hasSuffix(".log") else {
                return nil
            }

            let values = try url.resourceValues(forKeys: [
                .contentModificationDateKey,
                .fileSizeKey,
                .isRegularFileKey,
            ])
            guard values.isRegularFile == true else {
                return nil
            }

            return ActiveLogFile(
                url: url,
                modificationDate: values.contentModificationDate ?? .distantPast,
                sizeInBytes: values.fileSize ?? 0
            )
        }
    }

    private func archivedLogs(in logsDirectory: URL) throws -> [ArchivedLogFile] {
        try fileManager.contentsOfDirectory(
            at: logsDirectory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        .compactMap { url -> ArchivedLogFile? in
            let values = try url.resourceValues(forKeys: [.isRegularFileKey])
            guard values.isRegularFile == true else {
                return nil
            }

            return archivedLog(for: url)
        }
    }

    private func archivedLog(for url: URL) -> ArchivedLogFile? {
        let fileName = url.lastPathComponent
        guard fileName.count > 11 else {
            return nil
        }

        let archiveDateSuffix = String(fileName.suffix(10))
        guard let archiveDate = archiveDate(from: archiveDateSuffix) else {
            return nil
        }

        let baseName = String(fileName.dropLast(11))
        guard baseName.hasSuffix(".log") else {
            return nil
        }

        return ArchivedLogFile(
            url: url,
            baseLogName: baseName,
            archiveDate: archiveDate
        )
    }

    private func archive(_ currentLogURL: URL, to archiveURL: URL) throws {
        if fileManager.fileExists(atPath: archiveURL.path) {
            let existingContents = (try? String(contentsOf: archiveURL, encoding: .utf8)) ?? ""
            let currentContents = (try? String(contentsOf: currentLogURL, encoding: .utf8)) ?? ""
            try atomicFileWriter.replaceItem(at: archiveURL, permissions: 0o600) { temporaryURL in
                try (existingContents + currentContents).write(
                    to: temporaryURL,
                    atomically: false,
                    encoding: .utf8
                )
            }
            try? fileManager.removeItem(at: currentLogURL)
            return
        }

        try fileManager.moveItem(at: currentLogURL, to: archiveURL)
    }

    private func touchEmptyLog(at url: URL) throws {
        try atomicFileWriter.replaceItem(at: url, permissions: 0o600) { temporaryURL in
            try "".write(to: temporaryURL, atomically: false, encoding: .utf8)
        }
    }

    private func archiveDateString(for date: Date) -> String {
        let formatter = archiveDateFormatter()
        return formatter.string(from: date)
    }

    private func archiveDate(from string: String) -> Date? {
        let formatter = archiveDateFormatter()
        guard let date = formatter.date(from: string) else {
            return nil
        }

        return calendar.startOfDay(for: date)
    }

    private func archiveDateFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }

    private func retentionDays(for baseLogName: String, mainLogRetentionDays: Int) -> Int {
        switch baseLogName {
        case "debug.log":
            Self.debugLogRetentionDays
        default:
            mainLogRetentionDays
        }
    }
}

@MainActor
public final class DiagnosticsLogMaintenanceController {
    public typealias MaintenanceAction = @Sendable (Date) -> Void
    public typealias Sleep = @Sendable (Duration) async throws -> Void

    private let now: @Sendable () -> Date
    private let calendar: Calendar
    private let performMaintenance: MaintenanceAction
    private let sleep: Sleep
    private var task: Task<Void, Never>?

    public convenience init(
        service: DiagnosticsLogMaintenanceService,
        now: @escaping @Sendable () -> Date = Date.init,
        calendar: Calendar = .autoupdatingCurrent,
        sleep: @escaping Sleep = { try await Task.sleep(for: $0) }
    ) {
        self.init(
            now: now,
            calendar: calendar,
            performMaintenance: { timestamp in
                service.performMaintenance(now: timestamp)
            },
            sleep: sleep
        )
    }

    init(
        now: @escaping @Sendable () -> Date,
        calendar: Calendar,
        performMaintenance: @escaping MaintenanceAction,
        sleep: @escaping Sleep
    ) {
        self.now = now
        self.calendar = calendar
        self.performMaintenance = performMaintenance
        self.sleep = sleep
    }

    deinit {
        task?.cancel()
    }

    public func start() {
        guard task == nil else {
            return
        }

        performMaintenance(now())
        task = Task { [calendar, now, performMaintenance, sleep] in
            while !Task.isCancelled {
                let currentTime = now()
                let nextMidnight = Self.nextLocalMidnight(after: currentTime, calendar: calendar)

                do {
                    try await sleep(Self.sleepDuration(from: currentTime, to: nextMidnight))
                } catch is CancellationError {
                    return
                } catch {
                    return
                }

                performMaintenance(now())
            }
        }
    }

    public func stop() {
        task?.cancel()
        task = nil
    }

    static func nextLocalMidnight(after date: Date, calendar: Calendar) -> Date {
        let startOfDay = calendar.startOfDay(for: date)
        return calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay
    }

    static func sleepDuration(from now: Date, to later: Date) -> Duration {
        let interval = max(0, later.timeIntervalSince(now))
        let nanoseconds = Int64((interval * 1_000_000_000).rounded())
        return .nanoseconds(nanoseconds)
    }
}

private struct ActiveLogFile {
    let url: URL
    let modificationDate: Date
    let sizeInBytes: Int
}

private struct ArchivedLogFile {
    let url: URL
    let baseLogName: String
    let archiveDate: Date
}
