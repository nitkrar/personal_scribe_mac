import Foundation

public struct VerboseFileDiagnosticsSink: DiagnosticsSink {
    private let writer: DiagnosticsFileWriter
    private let isEnabled: @Sendable () -> Bool

    public init(
        storageLocatorProvider: @escaping @Sendable () -> any StorageLocator = { AppConfig.liveStorageLocator() },
        isEnabled: @escaping @Sendable () -> Bool = {
            DiagnosticLoggingMode.resolve() == .verbose
        },
        atomicFileWriter: any AtomicFileWriter = FileManagerAtomicFileWriter(),
        maxLogSizeBytes: Int = 1_000_000
    ) {
        writer = DiagnosticsFileWriter(
            fileName: "diagnostics.log",
            storageLocatorProvider: storageLocatorProvider,
            atomicFileWriter: atomicFileWriter,
            maxLogSizeBytes: maxLogSizeBytes
        )
        self.isEnabled = isEnabled
    }

    public func record(_ event: RedactedDiagnosticsEvent) async {
        guard isEnabled(), event.level != .error else {
            return
        }

        await writer.append(event)
    }
}
