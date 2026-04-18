import XCTest
import SeshatCore
@testable import SeshatTranscription

final class ModelPathTests: SeshatTranscriptionFilesystemTestCase {
    func testModelRootLivesUnderTestingOverride() throws {
        let modelsDirectory = try SeshatConfig.modelsDirectory()
        let modelRoot = FluidAudioTranscriber.modelRootDirectory(base: modelsDirectory)

        XCTAssertTrue(modelRoot.path.hasPrefix(modelsDirectory.path))
        XCTAssertEqual(modelRoot.lastPathComponent, SeshatConfig.modelId)
    }

    func testModelsExistRequiresExactFiveExpectedPaths() throws {
        let modelsDirectory = try SeshatConfig.modelsDirectory()
        let modelRoot = FluidAudioTranscriber.modelRootDirectory(base: modelsDirectory)

        try FileManager.default.createDirectory(at: modelRoot, withIntermediateDirectories: true)

        XCTAssertFalse(FluidAudioTranscriber.modelsExist(in: modelRoot))
    }
}
