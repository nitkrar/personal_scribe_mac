import Foundation

public enum SeshatConfig {
    public static let sampleRate: Double = 16_000
    public static let channelCount: Int = 1
    public static let modelId: String = "parakeet-tdt-0.6b-v2"

    public static func appSupportDirectory() throws -> URL {
        fatalError("Implemented in plan-00 step 5")
    }

    public static func modelsDirectory() throws -> URL {
        fatalError("Implemented in plan-00 step 5")
    }

    // Plan 00 D.1: test code mutates this from XCTest's default single-threaded path only.
    public nonisolated(unsafe) static var testingBaseDirectoryOverride: URL?
}
