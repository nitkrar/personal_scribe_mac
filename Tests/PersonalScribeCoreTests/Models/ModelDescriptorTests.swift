import XCTest
@testable import PersonalScribeCore

final class ModelDescriptorTests: XCTestCase {
    func testLegacyBuiltInDescriptorsDefaultTokenizerSourceAndRequiredChipFamilyToNil() {
        let legacyDescriptors = BuiltInModelCatalog.registeredModels.filter { $0.engine != .whisperKit }

        XCTAssertFalse(legacyDescriptors.isEmpty)
        for descriptor in legacyDescriptors {
            XCTAssertNil(
                descriptor.tokenizerSource,
                "\(descriptor.id) unexpectedly sets tokenizerSource outside the WhisperKit catalog rows"
            )
            XCTAssertNil(
                descriptor.requiredChipFamily,
                "\(descriptor.id) unexpectedly sets requiredChipFamily outside the WhisperKit catalog rows"
            )
        }
    }

    func testCodableDecodeWithoutSupportedLanguagesDefaultsToNil() throws {
        let descriptor = ModelDescriptor(
            id: "legacy",
            displayName: "Legacy",
            shortDescription: "legacy fixture",
            architecture: "Whisper",
            repository: "example/legacy",
            revision: "abc123",
            requiredRelativePaths: ["model.bin"],
            approximateSizeBytes: 1,
            engine: .whisperCpp
        )

        let data = try JSONEncoder().encode(descriptor)
        let decoded = try JSONDecoder().decode(ModelDescriptor.self, from: data)

        XCTAssertNil(decoded.supportedLanguages)
    }

    func testCodableRoundTripPreservesSupportedLanguages() throws {
        let descriptor = ModelDescriptor(
            id: "multilingual",
            displayName: "Multilingual",
            shortDescription: "fixture",
            architecture: "Whisper",
            repository: "example/multilingual",
            revision: "abc123",
            requiredRelativePaths: ["model.bin"],
            approximateSizeBytes: 1,
            engine: .whisperKit,
            supportedLanguages: ["en", "ja", "zh"]
        )

        let data = try JSONEncoder().encode(descriptor)
        let decoded = try JSONDecoder().decode(ModelDescriptor.self, from: data)

        XCTAssertEqual(decoded.supportedLanguages, ["en", "ja", "zh"])
    }
}
