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
    ///   2. `SeshatBaseDirectoryPath` UserDefaults key (user-facing override)
    ///   3. `~/Library/Application Support/Seshat/` (default)
    ///
    /// `testingBaseDirectoryOverride` takes precedence over all three for XCTest.
    public static func baseDirectory(
        defaults: UserDefaults = .standard,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> URL {
        try directoryLock.withLock {
            let directory = resolvedBaseDirectory(defaults: defaults, environment: environment)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            return directory.standardizedFileURL
        }
    }

    public static func setBaseDirectoryOverride(
        _ directory: URL?,
        defaults: UserDefaults = .standard
    ) {
        directoryLock.withLock {
            if let directory {
                defaults.set(directory.standardizedFileURL.path, forKey: userDefaultsKey)
            } else {
                defaults.removeObject(forKey: userDefaultsKey)
            }
        }
    }

    public static func modelsDirectory() throws -> URL {
        try subdirectory(named: "models")
    }

    /// Reserved for future modes/ feature. Directory is created lazily.
    public static func modesDirectory() throws -> URL {
        try subdirectory(named: "modes")
    }

    /// Reserved for future recordings/ feature. Directory is created lazily.
    public static func recordingsDirectory() throws -> URL {
        try subdirectory(named: "recordings")
    }

    /// Directory for a specific model's artifacts.
    public static func directory(for descriptor: ModelDescriptor) throws -> URL {
        let models = try modelsDirectory()
        let directory = models.appendingPathComponent(descriptor.id, isDirectory: true).standardizedFileURL
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    // MARK: - Legacy / test support

    // The `UserDefaults("SeshatBaseDirectoryPath")` override path only takes effect when the app runs from the packaged `.app` bundle with `CFBundleIdentifier = com.nitkrar.seshat`. When running via `swift run`, the executable's bundle identifier is the SPM default (empty or `SeshatAppKit`), so `defaults write com.nitkrar.seshat SeshatBaseDirectoryPath …` from a terminal is a silent no-op for the dev binary. The env var `SESHAT_BASE_DIR` works in both contexts. Unit tests pass because xctest runs in its own process domain and the same `UserDefaults.standard` read/write happens in-process.
    //
    // `testingBaseDirectoryOverride` is process-global. Tests that mutate it, `SeshatBaseDirectoryPath`,
    // or `SESHAT_BASE_DIR` must clean up in `defer` and serialize in test code rather than changing
    // Package.swift parallelism preemptively; only disable parallel testing if the suite actually flakes.
    // Plan 00 D.1: test code mutates this from XCTest's default single-threaded path only.
    public nonisolated(unsafe) static var testingBaseDirectoryOverride: URL?

    // MARK: - Private

    private static let directoryLock = NSLock()
    private static let userDefaultsKey = "SeshatBaseDirectoryPath"
    private static let envVarName = "SESHAT_BASE_DIR"

    private static func subdirectory(named name: String) throws -> URL {
        let base = try baseDirectory()
        let directory = base.appendingPathComponent(name, isDirectory: true).standardizedFileURL
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static func resolvedBaseDirectory(
        defaults: UserDefaults,
        environment: [String: String]
    ) -> URL {
        if let override = testingBaseDirectoryOverride {
            return override.appendingPathComponent("Seshat", isDirectory: true).standardizedFileURL
        }

        if let envPath = environment[envVarName], !envPath.isEmpty {
            return URL(fileURLWithPath: envPath, isDirectory: true).standardizedFileURL
        }

        if let userPath = defaults.string(forKey: userDefaultsKey), !userPath.isEmpty {
            return URL(fileURLWithPath: userPath, isDirectory: true).standardizedFileURL
        }

        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport.appendingPathComponent("Seshat", isDirectory: true).standardizedFileURL
    }
}
