import Foundation
import os

public struct ErrorFileDiagnosticsSink: DiagnosticsSink {
    private let writer: DiagnosticsFileWriter

    public init(
        storageLocatorProvider: @escaping @Sendable () -> any StorageLocator = { AppConfig.liveStorageLocator() },
        atomicFileWriter: any AtomicFileWriter = FileManagerAtomicFileWriter(),
        maxLogSizeBytes: Int = 1_000_000
    ) {
        writer = DiagnosticsFileWriter(
            fileName: "errors.log",
            storageLocatorProvider: storageLocatorProvider,
            atomicFileWriter: atomicFileWriter,
            maxLogSizeBytes: maxLogSizeBytes
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
    private let atomicFileWriter: any AtomicFileWriter
    private let fileManager: FileManager
    private let maxLogSizeBytes: Int
    private let fallbackLogger: Logger

    init(
        fileName: String,
        storageLocatorProvider: @escaping @Sendable () -> any StorageLocator,
        atomicFileWriter: any AtomicFileWriter,
        fileManager: FileManager = .default,
        maxLogSizeBytes: Int
    ) {
        self.fileName = fileName
        self.storageLocatorProvider = storageLocatorProvider
        self.atomicFileWriter = atomicFileWriter
        self.fileManager = fileManager
        self.maxLogSizeBytes = maxLogSizeBytes
        fallbackLogger = Logger(subsystem: AppBrand.logSubsystem, category: PersonalScribeLogCategory.app)
    }

    func append(_ event: RedactedDiagnosticsEvent) async {
        let locator = storageLocatorProvider()
        let logURL = locator
            .url(for: .logs)
            .appendingPathComponent(fileName)
            .standardizedFileURL
        let line = DiagnosticsLineRenderer.render(event) + "\n"

        do {
            try locator.ensureDirectoriesExist()

            let existingContents = (try? String(contentsOf: logURL, encoding: .utf8)) ?? ""
            let updatedContents = truncateIfNeeded(existingContents + line)

            try atomicFileWriter.replaceItem(at: logURL, permissions: 0o600) { temporaryURL in
                try updatedContents.write(to: temporaryURL, atomically: false, encoding: .utf8)
            }
        } catch {
            fallbackLogger.error("Failed to append diagnostics log line \(self.fileName, privacy: .public)")
        }
    }

    private func truncateIfNeeded(_ contents: String) -> String {
        let data = Data(contents.utf8)
        guard data.count > maxLogSizeBytes else {
            return contents
        }

        let suffix = data.suffix(maxLogSizeBytes)
        if let newlineIndex = suffix.firstIndex(of: 0x0A) {
            let trimmed = suffix[suffix.index(after: newlineIndex)...]
            return String(decoding: trimmed, as: UTF8.self)
        }

        return String(decoding: suffix, as: UTF8.self)
    }
}
