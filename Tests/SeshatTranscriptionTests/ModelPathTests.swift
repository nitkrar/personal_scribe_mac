import XCTest
import SeshatCore
@testable import SeshatTranscription

final class ModelPathTests: SeshatTranscriptionFilesystemTestCase {
    func testModelRootLivesUnderTestingOverride() throws {
        let descriptor = ModelRegistry.parakeetTDT06Bv2
        let modelsDirectory = try SeshatConfig.modelsDirectory()
        let modelRoot = try SeshatConfig.directory(for: descriptor)

        XCTAssertTrue(modelRoot.path.hasPrefix(modelsDirectory.path))
        XCTAssertEqual(modelRoot.lastPathComponent, descriptor.id)
    }

    func testModelsExistRequiresExactFiveExpectedPaths() throws {
        let descriptor = ModelRegistry.parakeetTDT06Bv2
        let modelRoot = try SeshatConfig.directory(for: descriptor)

        try FileManager.default.createDirectory(at: modelRoot, withIntermediateDirectories: true)

        XCTAssertFalse(FluidAudioTranscriber.modelsExist(in: modelRoot, descriptor: descriptor))
    }
}
