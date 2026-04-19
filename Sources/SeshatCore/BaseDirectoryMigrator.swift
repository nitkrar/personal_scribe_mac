import Foundation

public protocol BaseDirectoryMigrating: Sendable {
    func migrate(to newBase: URL) async throws -> MigrationReport
}

public enum MigrationReport: Sendable, Equatable {
    case noOp
    case migrated(movedSubdirs: [String], totalBytes: Int64)
}

public enum BaseDirectoryMigrationError: Error, Sendable, Equatable {
    case destinationNotWritable
    case partialFailure(failedSubdir: String)
}

extension BaseDirectoryMigrationError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .destinationNotWritable:
            "The selected base directory is not writable."
        case .partialFailure(let failedSubdir):
            "Migration stopped while moving \(failedSubdir)."
        }
    }

    public var failureReason: String? {
        switch self {
        case .destinationNotWritable:
            "Seshat could not create and remove a write probe in the selected directory."
        case .partialFailure:
            "Any subdirectories moved before the failure were rolled back when possible."
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .destinationNotWritable:
            "Choose a folder you can write to and try again."
        case .partialFailure(let failedSubdir):
            "Remove or rename any existing \(failedSubdir) folder in the destination, then retry."
        }
    }
}

/// `@unchecked Sendable` is safe here: all three stored properties
/// are Apple-documented thread-safe references:
///   • `FileManager.default` is documented thread-safe for the methods
///     we call (`fileExists`, `createDirectory`, `moveItem`, `removeItem`,
///     `attributesOfItem`, `enumerator`). Instance methods called on a
///     shared singleton are safe per Apple's docs.
///   • `UserDefaults` is documented thread-safe for `object(forKey:)`,
///     `set(_:forKey:)`, and `removeObject(forKey:)` — the only three
///     APIs used via this migrator's `AppConfig` helpers.
///   • `[String: String]` is value-typed and captured by copy.
/// No mutable state lives on the struct; the one `let` properties are
/// fully initialised in `init` and never replaced.
public struct BaseDirectoryMigrator: BaseDirectoryMigrating, @unchecked Sendable {
    private let fileManager: FileManager
    private let defaults: UserDefaults
    private let environment: [String: String]

    public init(
        fileManager: FileManager = .default,
        defaults: UserDefaults = .standard,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.fileManager = fileManager
        self.defaults = defaults
        self.environment = environment
    }

    public func migrate(to newBase: URL) async throws -> MigrationReport {
        let destinationBase = newBase.standardizedFileURL
        let sourceStorageLocator = AppConfig.liveStorageLocator(
            fileManager: fileManager,
            defaults: defaults,
            environment: environment
        )
        let destinationStorageLocator = FixedBaseDirectoryStorageLocator(
            baseDirectory: destinationBase,
            fileManager: fileManager
        )

        try validateWritableDestination(destinationBase)

        let sourceBase = sourceStorageLocator.baseDirectory
        if sourceBase == destinationBase {
            return .noOp
        }

        let presentSubdirectories = existingManagedSubdirectories(using: sourceStorageLocator)
        let totalBytes = try totalBytes(
            in: presentSubdirectories,
            using: sourceStorageLocator
        )

        var movedSubdirectories: [ManagedDirectory] = []
        for subdirectory in presentSubdirectories {
            let sourceURL = sourceStorageLocator.url(for: subdirectory)
            let destinationURL = destinationStorageLocator.url(for: subdirectory)

            do {
                try fileManager.moveItem(at: sourceURL, to: destinationURL)
                movedSubdirectories.append(subdirectory)
            } catch {
                rollbackMovedSubdirectories(
                    named: movedSubdirectories,
                    from: destinationStorageLocator,
                    backTo: sourceStorageLocator
                )
                throw BaseDirectoryMigrationError.partialFailure(failedSubdir: subdirectory.pathComponent)
            }
        }

        AppConfig.setBaseDirectoryOverride(destinationBase, defaults: defaults)
        try destinationStorageLocator.ensureDirectoriesExist()
        return .migrated(
            movedSubdirs: presentSubdirectories.map(\.pathComponent),
            totalBytes: totalBytes
        )
    }

    private func validateWritableDestination(_ destinationBase: URL) throws {
        let probeURL = destinationBase.appendingPathComponent(
            ".seshat-migration-probe-\(UUID().uuidString)",
            isDirectory: false
        )
        let created = fileManager.createFile(atPath: probeURL.path, contents: Data(), attributes: nil)
        guard created else {
            throw BaseDirectoryMigrationError.destinationNotWritable
        }

        do {
            try fileManager.removeItem(at: probeURL)
        } catch {
            throw BaseDirectoryMigrationError.destinationNotWritable
        }
    }

    private func existingManagedSubdirectories(
        using storageLocator: any StorageLocator
    ) -> [ManagedDirectory] {
        ManagedDirectory.allCases.filter { directory in
            let url = storageLocator.url(for: directory)
            var isDirectory = ObjCBool(false)
            let exists = fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory)
            return exists && isDirectory.boolValue
        }
    }

    private func totalBytes(
        in directories: [ManagedDirectory],
        using storageLocator: any StorageLocator
    ) throws -> Int64 {
        try directories.reduce(into: Int64.zero) { partialResult, directory in
            partialResult += try ManagedDirectoryByteCounter.totalBytes(
                in: storageLocator.url(for: directory),
                fileManager: fileManager
            )
        }
    }

    private func rollbackMovedSubdirectories(
        named movedSubdirectories: [ManagedDirectory],
        from destinationStorageLocator: any StorageLocator,
        backTo sourceStorageLocator: any StorageLocator
    ) {
        for subdirectory in movedSubdirectories.reversed() {
            let movedURL = destinationStorageLocator.url(for: subdirectory)
            let originalURL = sourceStorageLocator.url(for: subdirectory)

            do {
                try fileManager.moveItem(at: movedURL, to: originalURL)
            } catch {
                NSLog(
                    "BaseDirectoryMigrator rollback failed for %@: %@",
                    subdirectory.pathComponent,
                    error.localizedDescription
                )
            }
        }
    }
}
