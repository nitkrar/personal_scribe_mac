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
}
