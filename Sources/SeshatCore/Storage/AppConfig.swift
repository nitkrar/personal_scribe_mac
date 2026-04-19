import Foundation

public enum AppConfig {
    public static let sampleRate: Double = 16_000
    public static let channelCount: Int = 1

    // DEPRECATED shim — keeps existing callers aligned while storage ownership moves out of SeshatConfig.
    public static let modelId: String = ModelRegistry.defaultModelId

    public nonisolated(unsafe) static var testingBaseDirectoryOverride: URL?

    static let baseDirectoryUserDefaultsKey = "SeshatBaseDirectoryPath"
    static let baseDirectoryEnvironmentVariableName = "SESHAT_BASE_DIR"

    private static let overrideLock = NSLock()

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
            if let directory {
                defaults.set(directory.standardizedFileURL.path, forKey: baseDirectoryUserDefaultsKey)
            } else {
                defaults.removeObject(forKey: baseDirectoryUserDefaultsKey)
            }
        }
    }

    static func resolvedBaseDirectory(
        defaults: UserDefaults,
        environment: [String: String],
        fileManager: FileManager,
        testingBaseDirectoryOverride: URL?
    ) -> URL {
        if let testingBaseDirectoryOverride {
            return testingBaseDirectoryOverride
                .appendingPathComponent("Seshat", isDirectory: true)
                .standardizedFileURL
        }

        if let envPath = environment[baseDirectoryEnvironmentVariableName], !envPath.isEmpty {
            return URL(fileURLWithPath: envPath, isDirectory: true).standardizedFileURL
        }

        if let userPath = defaults.string(forKey: baseDirectoryUserDefaultsKey), !userPath.isEmpty {
            return URL(fileURLWithPath: userPath, isDirectory: true).standardizedFileURL
        }

        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport.appendingPathComponent("Seshat", isDirectory: true).standardizedFileURL
    }
}
