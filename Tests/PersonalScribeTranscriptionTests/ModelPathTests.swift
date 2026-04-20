import XCTest
import PersonalScribeCore
@testable import PersonalScribeTranscription

final class ModelPathTests: PersonalScribeTranscriptionFilesystemTestCase {
    func testModelRootLivesUnderTestingOverride() throws {
        let descriptor = BuiltInModelCatalog.parakeetTDT06Bv2
        let modelsDirectory = try AppConfig.modelsDirectory()
        let modelRoot = try AppConfig.directory(for: descriptor)

        XCTAssertTrue(modelRoot.path.hasPrefix(modelsDirectory.path))
        XCTAssertEqual(modelRoot.lastPathComponent, descriptor.id)
    }

    func testModelsExistRequiresExactFiveExpectedPaths() throws {
        let descriptor = BuiltInModelCatalog.parakeetTDT06Bv2
        let modelRoot = try AppConfig.directory(for: descriptor)

        try FileManager.default.createDirectory(at: modelRoot, withIntermediateDirectories: true)

        XCTAssertFalse(ModelArtifactStaging.modelsExist(in: modelRoot, descriptor: descriptor))
    }
}
