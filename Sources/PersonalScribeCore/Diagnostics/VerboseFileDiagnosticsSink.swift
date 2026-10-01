import Foundation

/// Writes info + notice events to diagnostics.log. Always on, per
/// docs/INSTRUMENTATION_PRINCIPLES.md: this is the production evidence
/// trail (OSLog keeps info only in memory). Size is bounded by the
/// per-file cap plus daily rotation and retention.
public struct VerboseFileDiagnosticsSink: DiagnosticsSink {
    private let writer: DiagnosticsFileWriter

    public init(
        storageLocatorProvider: @escaping @Sendable () -> any StorageLocator = { AppConfig.liveStorageLocator() },
        atomicFileWriter: any AtomicFileWriter = FileManagerAtomicFileWriter(),
        maxLogSizeBytes: Int = 1_000_000
    ) {
        writer = DiagnosticsFileWriter(
            fileName: "diagnostics.log",
            storageLocatorProvider: storageLocatorProvider,
            atomicFileWriter: atomicFileWriter,
            maxLogSizeBytes: maxLogSizeBytes
        )
    }

    public func record(_ event: RedactedDiagnosticsEvent) async {
        guard event.level == .info || event.level == .notice else {
            return
        }

        await writer.append(event)
    }
}
