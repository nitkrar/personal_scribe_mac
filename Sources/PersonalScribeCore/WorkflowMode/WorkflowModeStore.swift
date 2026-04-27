import Foundation
import PersonalScribeCore

/// Disk-backed implementation of `WorkflowModeStoring` (#078.25).
///
/// File layout: `<storageLocator.baseDirectory>/workflow-modes.json`
/// (per L21 + L23, single document — `WorkflowModeDocument`).
///
/// First-launch behavior: `load()` returns a fresh
/// `WorkflowModeDocument()` (default values) when the file is missing.
/// The first subsequent `save()` writes the file; we do NOT write on
/// load alone — readers that don't mutate shouldn't change disk state.
///
/// Decode-failure behavior: throws `WorkflowModeStoreError.decodeFailed`.
/// Callers (registry init) decide whether to fall back to the default
/// document; this type doesn't silently swallow corruption.
///
/// Thread-safety: `Sendable` via locking. `load`/`save` serialise
/// against each other so one user can't observe a half-written file.
public final class WorkflowModeStore: WorkflowModeStoring, @unchecked Sendable {
    private let lock = NSLock()
    private let baseDirectory: URL
    private let fileManager: FileManager

    public init(
        storageLocator: any StorageLocator = AppConfig.liveStorageLocator(),
        fileManager: FileManager = .default
    ) {
        self.baseDirectory = storageLocator.baseDirectory
        self.fileManager = fileManager
    }

    /// Test-friendly init: take `baseDirectory` directly without
    /// requiring a `StorageLocator`.
    public init(baseDirectory: URL, fileManager: FileManager = .default) {
        self.baseDirectory = baseDirectory
        self.fileManager = fileManager
    }

    public func load() throws -> WorkflowModeDocument {
        try lock.withLock {
            let url = fileURL
            guard fileManager.fileExists(atPath: url.path) else {
                return WorkflowModeDocument()
            }
            let data: Data
            do {
                data = try Data(contentsOf: url)
            } catch {
                throw WorkflowModeStoreError.readFailed(underlying: error)
            }
            do {
                return try JSONDecoder().decode(WorkflowModeDocument.self, from: data)
            } catch {
                throw WorkflowModeStoreError.decodeFailed(underlying: error)
            }
        }
    }

    public func save(_ document: WorkflowModeDocument) throws {
        try lock.withLock {
            try ensureBaseDirectoryExists()
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data: Data
            do {
                data = try encoder.encode(document)
            } catch {
                throw WorkflowModeStoreError.encodeFailed(underlying: error)
            }
            do {
                try data.write(to: fileURL, options: .atomic)
            } catch {
                throw WorkflowModeStoreError.writeFailed(underlying: error)
            }
        }
    }

    // MARK: - Internals

    private var fileURL: URL {
        baseDirectory.appendingPathComponent("workflow-modes.json", isDirectory: false)
    }

    private func ensureBaseDirectoryExists() throws {
        var isDirectory: ObjCBool = false
        if !fileManager.fileExists(atPath: baseDirectory.path, isDirectory: &isDirectory) {
            try fileManager.createDirectory(
                at: baseDirectory,
                withIntermediateDirectories: true
            )
        }
    }
}

public enum WorkflowModeStoreError: Error {
    case readFailed(underlying: Error)
    case writeFailed(underlying: Error)
    case decodeFailed(underlying: Error)
    case encodeFailed(underlying: Error)
}
