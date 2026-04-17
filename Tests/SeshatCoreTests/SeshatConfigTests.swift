import Foundation
import XCTest
@testable import SeshatCore

final class SeshatConfigTests: XCTestCase {
    func testModelsDirectoryNestsUnderAppSupport() throws {
        let baseDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        SeshatConfig.testingBaseDirectoryOverride = baseDirectory
        defer { SeshatConfig.testingBaseDirectoryOverride = nil }

        let appSupport = try SeshatConfig.appSupportDirectory()
        let models = try SeshatConfig.modelsDirectory()

        XCTAssertEqual(
            appSupport,
            baseDirectory
                .appendingPathComponent("Seshat", isDirectory: true)
                .standardizedFileURL
        )
        XCTAssertEqual(
            models,
            appSupport
                .appendingPathComponent("models", isDirectory: true)
                .standardizedFileURL
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: appSupport.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: models.path))
    }
}
