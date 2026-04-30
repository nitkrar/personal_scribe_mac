import Foundation

public struct RingBufferDiagnosticsSink: DiagnosticsSink {
    private let store: DiagnosticsStore
    private let minimumLevelProvider: @Sendable () -> DiagnosticsLevel

    public init(
        store: DiagnosticsStore,
        minimumLevelProvider: @escaping @Sendable () -> DiagnosticsLevel
    ) {
        self.store = store
        self.minimumLevelProvider = minimumLevelProvider
    }

    public func record(_ event: RedactedDiagnosticsEvent) async {
        guard event.level >= minimumLevelProvider() else {
            return
        }

        await store.append(event)
    }
}
