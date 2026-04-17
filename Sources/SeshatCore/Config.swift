import Foundation

public enum SeshatConfig {
    public static let sampleRate: Double = 16_000
    public static let channelCount: Int = 1
    public static let modelId: String = "parakeet-tdt-0.6b-v2"

    private static let directoryLock = NSLock()

    public static func appSupportDirectory() throws -> URL {
        try directoryLock.withLock {
            let directory = resolvedBaseDirectory()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            return directory.standardizedFileURL
        }
    }

    public static func modelsDirectory() throws -> URL {
        try directoryLock.withLock {
            let directory = resolvedBaseDirectory()
                .appendingPathComponent("models", isDirectory: true)
                .standardizedFileURL
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            return directory
        }
    }

    // Plan 00 D.1: test code mutates this from XCTest's default single-threaded path only.
    public nonisolated(unsafe) static var testingBaseDirectoryOverride: URL?

    private static func resolvedBaseDirectory() -> URL {
        if let override = testingBaseDirectoryOverride {
            return override
                .appendingPathComponent("Seshat", isDirectory: true)
                .standardizedFileURL
        }

        let baseDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return baseDirectory
            .appendingPathComponent("Seshat", isDirectory: true)
            .standardizedFileURL
    }
}
