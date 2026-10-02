import Foundation
import os

public struct ErrorFileDiagnosticsSink: DiagnosticsSink {
    private let writer: DiagnosticsFileWriter

    public init(
        storageLocatorProvider: @escaping @Sendable () -> any StorageLocator = { AppConfig.liveStorageLocator() },
        options: DiagnosticsLogFileOptions = DiagnosticsLogFileOptions()
    ) {
        writer = DiagnosticsFileWriter(
            fileName: "errors.log",
            storageLocatorProvider: storageLocatorProvider,
            options: options
        )
    }

    public func record(_ event: RedactedDiagnosticsEvent) async {
        guard event.level == .error else {
            return
        }

        await writer.append(event)
    }
}

actor DiagnosticsFileWriter {
    private let fileName: String
    private let storageLocatorProvider: @Sendable () -> any StorageLocator
    private let options: DiagnosticsLogFileOptions
    private let fileManager: FileManager
    private let fallbackLogger: Logger

    init(
        fileName: String,
        storageLocatorProvider: @escaping @Sendable () -> any StorageLocator,
        options: DiagnosticsLogFileOptions,
        fileManager: FileManager = .default
    ) {
        self.fileName = fileName
        self.storageLocatorProvider = storageLocatorProvider
        self.options = options
        self.fileManager = fileManager
        fallbackLogger = Logger(subsystem: AppBrand.logSubsystem, category: PersonalScribeLogCategory.app)
    }

    func append(_ event: RedactedDiagnosticsEvent) async {
        let locator = storageLocatorProvider()
        let logURL = locator
            .url(for: .logs)
            .appendingPathComponent(fileName)
            .standardizedFileURL
        let line = Data((DiagnosticsLineRenderer.render(event) + "\n").utf8)

        do {
            try locator.ensureDirectoriesExist()
            try fileManager.createDirectory(
                at: logURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try rollOverIfFull(logURL, adding: line.count)
            if !fileManager.fileExists(atPath: logURL.path) {
                guard fileManager.createFile(
                    atPath: logURL.path,
                    contents: nil,
                    attributes: [.posixPermissions: 0o600]
                ) else {
                    throw CocoaError(.fileWriteUnknown)
                }
            }

            let handle = try FileHandle(forWritingTo: logURL)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: line)
        } catch {
            fallbackLogger.error("Failed to append diagnostics log line \(self.fileName, privacy: .public)")
        }
    }

    private func rollOverIfFull(_ logURL: URL, adding byteCount: Int) throws {
        let attributes = try? fileManager.attributesOfItem(atPath: logURL.path)
        let size = (attributes?[.size] as? NSNumber)?.intValue ?? 0
        guard size > 0, size + byteCount > options.maxLogSizeBytes else {
            return
        }

        let archiveURL = DiagnosticsLogArchiveName.nextURL(
            forActiveLog: logURL,
            day: options.calendar.startOfDay(for: options.now()),
            calendar: options.calendar,
            fileManager: fileManager
        )
        try fileManager.moveItem(at: logURL, to: archiveURL)
        options.onRollover()
    }
}
