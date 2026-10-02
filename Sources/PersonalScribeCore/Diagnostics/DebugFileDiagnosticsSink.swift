import Foundation

public struct DebugFileDiagnosticsSink: DiagnosticsSink {
    private let writer: DiagnosticsFileWriter

    public init(
        storageLocatorProvider: @escaping @Sendable () -> any StorageLocator = { AppConfig.liveStorageLocator() },
        options: DiagnosticsLogFileOptions = DiagnosticsLogFileOptions()
    ) {
        writer = DiagnosticsFileWriter(
            fileName: "debug.log",
            storageLocatorProvider: storageLocatorProvider,
            options: options
        )
    }

    public func record(_ event: RedactedDiagnosticsEvent) async {
        guard event.level == .debug else {
            return
        }

        await writer.append(event)
    }
}
