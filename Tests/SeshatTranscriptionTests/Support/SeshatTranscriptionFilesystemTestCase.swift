import Foundation
import XCTest
import SeshatCore

class SeshatTranscriptionFilesystemTestCase: XCTestCase {
    var testRoot: URL!

    override func setUp() async throws {
        try await super.setUp()

        testRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: testRoot,
            withIntermediateDirectories: true
        )
        SeshatConfig.testingBaseDirectoryOverride = testRoot
    }

    override func tearDown() async throws {
        SeshatConfig.testingBaseDirectoryOverride = nil
        try? FileManager.default.removeItem(at: testRoot)
        try await super.tearDown()
    }
}
