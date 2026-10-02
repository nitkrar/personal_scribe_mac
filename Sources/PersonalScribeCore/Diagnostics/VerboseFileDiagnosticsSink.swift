import Foundation

/// Writes info + notice events to diagnostics.log. Always on, per
/// docs/INSTRUMENTATION_PRINCIPLES.md: this is the production evidence
/// trail (OSLog keeps info only in memory).
public struct VerboseFileDiagnosticsSink: DiagnosticsSink {
    private let writer: DiagnosticsFileWriter

    public init(
        storageLocatorProvider: @escaping @Sendable () -> any StorageLocator = { AppConfig.liveStorageLocator() },
        options: DiagnosticsLogFileOptions = DiagnosticsLogFileOptions()
    ) {
        writer = DiagnosticsFileWriter(
            fileName: "diagnostics.log",
            storageLocatorProvider: storageLocatorProvider,
            options: options
        )
    }

    public func record(_ event: RedactedDiagnosticsEvent) async {
        guard event.level == .info || event.level == .notice else {
            return
        }

        await writer.append(event)
    }
}
