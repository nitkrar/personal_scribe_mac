import Foundation

public actor DiagnosticsStore {
    private let capacity: Int
    private var events: [RedactedDiagnosticsEvent]
    private var continuations: [UUID: AsyncStream<[RedactedDiagnosticsEvent]>.Continuation] = [:]

    public init(capacity: Int = 200) {
        self.capacity = max(1, capacity)
        events = []
    }

    public func append(_ event: RedactedDiagnosticsEvent) {
        events.insert(event, at: 0)
        if events.count > capacity {
            events.removeLast(events.count - capacity)
        }
        publish()
    }

    public func snapshot() -> [RedactedDiagnosticsEvent] {
        events
    }

    public func stream() -> AsyncStream<[RedactedDiagnosticsEvent]> {
        let id = UUID()

        return AsyncStream { continuation in
            continuation.yield(events)
            continuations[id] = continuation
            continuation.onTermination = { [weak self] _ in
                Task {
                    await self?.removeContinuation(id: id)
                }
            }
        }
    }

    private func removeContinuation(id: UUID) {
        continuations[id] = nil
    }

    private func publish() {
        for continuation in continuations.values {
            continuation.yield(events)
        }
    }
}
