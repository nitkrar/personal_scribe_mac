import Foundation

/// `@unchecked Sendable` is safe here because the stored `FileManager` is only used
/// through Apple-documented thread-safe directory creation APIs.
struct FixedBaseDirectoryStorageLocator: StorageLocator, @unchecked Sendable {
    let baseDirectory: URL
    private let fileManager: FileManager
    private let managedDirectoryOverrides: [ManagedDirectory: URL]

    init(
        baseDirectory: URL,
        fileManager: FileManager = .default,
        managedDirectoryOverrides: [ManagedDirectory: URL] = [:]
    ) {
        self.baseDirectory = baseDirectory.standardizedFileURL
        self.fileManager = fileManager
        self.managedDirectoryOverrides = Dictionary(
            uniqueKeysWithValues: managedDirectoryOverrides.map { entry in
                (entry.key, entry.value.standardizedFileURL)
            }
        )
    }

    func url(for directory: ManagedDirectory) -> URL {
        managedDirectoryOverrides[directory] ??
            baseDirectory
            .appendingPathComponent(directory.pathComponent, isDirectory: true)
            .standardizedFileURL
    }

    func ensureDirectoriesExist() throws {
        try fileManager.createDirectory(at: baseDirectory, withIntermediateDirectories: true)

        for directory in ManagedDirectory.allCases {
            try fileManager.createDirectory(
                at: url(for: directory),
                withIntermediateDirectories: true
            )
        }
    }
}
