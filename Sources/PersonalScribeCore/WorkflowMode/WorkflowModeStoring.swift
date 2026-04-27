import Foundation
import PersonalScribeCore

/// Persistence seam for `WorkflowModeRegistry` (#078.24).
///
/// Production conformer: `WorkflowModeStore` (#078.25) — JSON on disk
/// at `<AppConfig.baseDirectory()>/workflow-modes.json`.
///
/// Test conformer: `InMemoryWorkflowModeStore` — keeps the document in
/// memory, no I/O.
///
/// Why a protocol: the registry's behaviour (active mode, custom modes,
/// validation) is testable without disk; the disk concern lives behind
/// this seam so tests can run fast and fakes don't need a temp dir.
public protocol WorkflowModeStoring: Sendable {
    func load() throws -> WorkflowModeDocument
    func save(_ document: WorkflowModeDocument) throws
}

/// In-memory implementation for tests + first-boot transients.
public final class InMemoryWorkflowModeStore: WorkflowModeStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var document: WorkflowModeDocument

    public init(initial: WorkflowModeDocument = WorkflowModeDocument()) {
        self.document = initial
    }

    public func load() throws -> WorkflowModeDocument {
        lock.withLock { document }
    }

    public func save(_ document: WorkflowModeDocument) throws {
        lock.withLock { self.document = document }
    }
}
