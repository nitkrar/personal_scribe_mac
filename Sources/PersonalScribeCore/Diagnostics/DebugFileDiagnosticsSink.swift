import Foundation

public struct DebugFileDiagnosticsSink: DiagnosticsSink {
    private let writer: DiagnosticsFileWriter

    public init(
        storageLocatorProvider: @escaping @Sendable () -> any StorageLocator = { AppConfig.liveStorageLocator() },
        atomicFileWriter: any AtomicFileWriter = FileManagerAtomicFileWriter(),
        maxLogSizeBytes: Int = 1_000_000
    ) {
        writer = DiagnosticsFileWriter(
            fileName: "debug.log",
            storageLocatorProvider: storageLocatorProvider,
            atomicFileWriter: atomicFileWriter,
            maxLogSizeBytes: maxLogSizeBytes
        )
    }

    public func record(_ event: RedactedDiagnosticsEvent) async {
        guard event.level == .debug else {
            return
        }

        await writer.append(event)
    }
}
