import Foundation

public enum AppConfig {
    public static let sampleRate: Double = 16_000
    public static let channelCount: Int = 1

    public nonisolated(unsafe) static var testingBaseDirectoryOverride: URL?

    static let baseDirectoryUserDefaultsKey = "BaseDirectoryPath"
    static let baseDirectoryEnvironmentVariableName = "PERSONAL_SCRIBE_BASE_DIR"

    private static let overrideLock = NSLock()
    private static let directoryLock = NSLock()

    public static func liveStorageLocator(
        fileManager: FileManager = .default,
        defaults: UserDefaults = .standard,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> AppStorageLocator {
        AppStorageLocator(
            fileManager: fileManager,
            defaults: defaults,
            environment: environment,
            testingBaseDirectoryOverrideProvider: { AppConfig.testingBaseDirectoryOverride }
        )
    }

    public static func setBaseDirectoryOverride(
        _ directory: URL?,
        defaults: UserDefaults = .standard
    ) {
        overrideLock.withLock {
            baseDirectoryPathPreference(defaults: defaults)
                .persist(directory?.standardizedFileURL.path)
        }
    }

    public static func baseDirectoryPathPreference(
        defaults: UserDefaults = .standard
    ) -> Preference<String?> {
        Preference(key: baseDirectoryUserDefaultsKey, default: nil, defaults: defaults)
    }

    // MARK: - Directory accessors

    /// Resolution order (first match wins):
    ///   1. `SESHAT_BASE_DIR` environment variable (dev/test convenience)
    ///   2. `BaseDirectoryPath` UserDefaults key (user-facing override)
    ///   3. `~/Library/Application Support/personal_scribe/` (default)
    ///
    /// `testingBaseDirectoryOverride` takes precedence over all three for XCTest.
    public static func baseDirectory(
        defaults: UserDefaults = .standard,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> URL {
        try directoryLock.withLock {
            let directory = liveStorageLocator(
                fileManager: .default,
                defaults: defaults,
                environment: environment
            ).baseDirectory
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            return directory.standardizedFileURL
        }
    }

    public static func modelsDirectory() throws -> URL {
        try subdirectory(for: .models)
    }

    /// Reserved for future recordings/ feature. Directory is created lazily.
    public static func recordingsDirectory() throws -> URL {
        try subdirectory(for: .recordings)
    }

    /// Directory for a specific model's artifacts.
    public static func directory(for descriptor: ModelDescriptor) throws -> URL {
        let storageLocator = liveStorageLocator()
        let directory = storageLocator
            .url(for: .models)
            .appendingPathComponent(descriptor.id, isDirectory: true)
            .standardizedFileURL
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    // MARK: - Internal

    static func resolvedBaseDirectory(
        defaults: UserDefaults,
        environment: [String: String],
        fileManager: FileManager,
        testingBaseDirectoryOverride: URL?
    ) -> URL {
        if let testingBaseDirectoryOverride {
            return testingBaseDirectoryOverride
                .appendingPathComponent("personal_scribe", isDirectory: true)
                .standardizedFileURL
        }

        if let envPath = environment[baseDirectoryEnvironmentVariableName], !envPath.isEmpty {
            return URL(fileURLWithPath: envPath, isDirectory: true).standardizedFileURL
        }

        if let userPath = baseDirectoryPathPreference(defaults: defaults).resolve(), !userPath.isEmpty {
            return URL(fileURLWithPath: userPath, isDirectory: true).standardizedFileURL
        }

        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport.appendingPathComponent("personal_scribe", isDirectory: true).standardizedFileURL
    }

    private static func subdirectory(for managedDirectory: ManagedDirectory) throws -> URL {
        let storageLocator = liveStorageLocator()
        let directory = storageLocator.url(for: managedDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
