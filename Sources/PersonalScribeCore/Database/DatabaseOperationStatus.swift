import Foundation

/// Per-operation status reported by `TranscriptRepository` after each read
/// or write attempt. Backlog #043 framing: this is **not** a "database
/// health" signal — it's a strict per-op outcome. A single `.readFailed`
/// followed by `.readSucceeded` simply means the last op failed then the
/// next one recovered; there is no latched "unhealthy" state.
public enum DatabaseOperationStatus: Sendable, Equatable {
    case idle
    case readSucceeded
    case readFailed
    case writeSucceeded
    case writeFailed
}

/// Sink for per-operation status updates. Must be safe to call from any
/// isolation context — `TranscriptRepository` is a `Sendable` struct used
/// from arbitrary tasks, so the call site is not pinned to the main actor.
public protocol DatabaseOperationObserving: Sendable {
    func record(_ status: DatabaseOperationStatus)
}

/// No-op observer used as the default injection when a caller does not
/// wire a real observer. Keeps the `TranscriptRepository` init non-
/// optional (plan §043 concern: a silent nil observer would make prod
/// forget-to-inject bugs invisible; the null default is explicit).
public final class NullDatabaseOperationObserver: DatabaseOperationObserving {
    public init() {}
    public func record(_: DatabaseOperationStatus) {}
}

/// Main-actor `ObservableObject` that holds the latest per-op status for
/// SwiftUI subscribers. The `record(_:)` entry point is `nonisolated` so
/// the repository (and any task hop it runs on) can call it without an
/// `await`; the state mutation is hopped onto the main actor via an
/// unstructured `Task`.
///
/// Ordering caveat: because `record(_:)` spawns a main-actor Task, the
/// published `current` value updates *asynchronously* after the repo
/// method returns. Callers that need to observe a status change after a
/// repo call must poll / await the published value rather than reading
/// it synchronously.
@MainActor
public final class DatabaseOperationObserver: ObservableObject, DatabaseOperationObserving {
    @Published public private(set) var current: DatabaseOperationStatus = .idle

    public init() {}

    public nonisolated func record(_ status: DatabaseOperationStatus) {
        Task { @MainActor in
            self.current = status
        }
    }
}
