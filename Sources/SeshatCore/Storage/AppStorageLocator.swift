import Foundation

/// `@unchecked Sendable` is safe here because the stored references are thread-safe for the APIs used:
/// `FileManager` creates directories and resolves Application Support URLs, `UserDefaults` reads the
/// override string, and the environment snapshot plus override provider are immutable after init.
public struct AppStorageLocator: StorageLocator, @unchecked Sendable {
    private let fileManager: FileManager
    private let defaults: UserDefaults
    private let environment: [String: String]
    private let testingBaseDirectoryOverrideProvider: @Sendable () -> URL?

    public init(
        fileManager: FileManager = .default,
        defaults: UserDefaults = .standard,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        testingBaseDirectoryOverrideProvider: @escaping @Sendable () -> URL? = {
            AppConfig.testingBaseDirectoryOverride
        }
    ) {
        self.fileManager = fileManager
        self.defaults = defaults
        self.environment = environment
        self.testingBaseDirectoryOverrideProvider = testingBaseDirectoryOverrideProvider
    }

    public var baseDirectory: URL {
        AppConfig.resolvedBaseDirectory(
            defaults: defaults,
            environment: environment,
            fileManager: fileManager,
            testingBaseDirectoryOverride: testingBaseDirectoryOverrideProvider()
        )
    }

    public func url(for directory: ManagedDirectory) -> URL {
        baseDirectory
            .appendingPathComponent(directory.pathComponent, isDirectory: true)
            .standardizedFileURL
    }

    public func ensureDirectoriesExist() throws {
        let resolvedBaseDirectory = baseDirectory
        try fileManager.createDirectory(at: resolvedBaseDirectory, withIntermediateDirectories: true)

        for directory in ManagedDirectory.allCases {
            try fileManager.createDirectory(
                at: resolvedBaseDirectory.appendingPathComponent(directory.pathComponent, isDirectory: true),
                withIntermediateDirectories: true
            )
        }
    }
}
