import Foundation

public enum SeshatConfig {
    public static let sampleRate: Double = 16_000
    public static let channelCount: Int = 1

    // DEPRECATED shim — keeps existing callers compiling.
    // Prefer ModelRegistry.defaultModelId and ModelDescriptor throughout new code.
    public static let modelId: String = ModelRegistry.defaultModelId

    // MARK: - Base directory resolution

    /// Resolution order (first match wins):
    ///   1. `SESHAT_BASE_DIR` environment variable (dev/test convenience)
    ///   2. `BaseDirectoryPath` UserDefaults key (user-facing override)
    ///   3. `~/Library/Application Support/Seshat/` (default)
    ///
    /// `testingBaseDirectoryOverride` takes precedence over all three for XCTest.
    public static func baseDirectory(
        defaults: UserDefaults = .standard,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> URL {
        try directoryLock.withLock {
            let directory = AppConfig.liveStorageLocator(
                fileManager: .default,
                defaults: defaults,
                environment: environment
            ).baseDirectory
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            return directory.standardizedFileURL
        }
    }

    public static func setBaseDirectoryOverride(
        _ directory: URL?,
        defaults: UserDefaults = .standard
    ) {
        AppConfig.setBaseDirectoryOverride(directory, defaults: defaults)
    }

    public static func baseDirectoryPathPreference(
        defaults: UserDefaults = .standard
    ) -> Preference<String?> {
        Preference(key: AppConfig.baseDirectoryUserDefaultsKey, default: nil, defaults: defaults)
    }

    public static func modelsDirectory() throws -> URL {
        try subdirectory(for: .models)
    }

    /// Reserved for future modes/ feature. Directory is created lazily.
    public static func modesDirectory() throws -> URL {
        try subdirectory(for: .modes)
    }

    /// Reserved for future recordings/ feature. Directory is created lazily.
    public static func recordingsDirectory() throws -> URL {
        try subdirectory(for: .recordings)
    }

    /// Directory for a specific model's artifacts.
    public static func directory(for descriptor: ModelDescriptor) throws -> URL {
        let storageLocator = AppConfig.liveStorageLocator()
        let directory = storageLocator
            .url(for: .models)
            .appendingPathComponent(descriptor.id, isDirectory: true)
            .standardizedFileURL
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    // MARK: - Legacy / test support

    // The `UserDefaults("BaseDirectoryPath")` override path only takes effect when the app runs from the packaged `.app` bundle with `CFBundleIdentifier = com.nitkrar.seshat`. When running via `swift run`, the executable's bundle identifier is the SPM default (empty or `SeshatAppKit`), so `defaults write com.nitkrar.seshat BaseDirectoryPath …` from a terminal is a silent no-op for the dev binary. The env var `SESHAT_BASE_DIR` works in both contexts. Unit tests pass because xctest runs in its own process domain and the same `UserDefaults.standard` read/write happens in-process.
    //
    // `testingBaseDirectoryOverride` is process-global. Tests that mutate it, `BaseDirectoryPath`,
    // or `SESHAT_BASE_DIR` must clean up in `defer` and serialize in test code rather than changing
    // Package.swift parallelism preemptively; only disable parallel testing if the suite actually flakes.
    // Plan 00 D.1: test code mutates this from XCTest's default single-threaded path only.
    public nonisolated(unsafe) static var testingBaseDirectoryOverride: URL? {
        get { AppConfig.testingBaseDirectoryOverride }
        set { AppConfig.testingBaseDirectoryOverride = newValue }
    }

    // MARK: - Private

    private static let directoryLock = NSLock()

    private static func subdirectory(for managedDirectory: ManagedDirectory) throws -> URL {
        let storageLocator = AppConfig.liveStorageLocator()
        let directory = storageLocator.url(for: managedDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}

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
