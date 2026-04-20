import XCTest
@testable import PersonalScribeCore
@testable import PersonalScribeTranscription

final class FluidAudioTranscriberCompileTests: XCTestCase {
    func testFluidAudioTranscriberConformsToTranscribing() {
        let transcriber: any Transcribing = FluidAudioTranscriber(
            logger: PersonalScribeLogger(category: PersonalScribeLogCategory.transcription)
        )

        XCTAssertNotNil(transcriber)
    }

    func testDefaultInitializerUsesRegistryDefaultModelId() async {
        let transcriber = FluidAudioTranscriber(
            logger: PersonalScribeLogger(category: PersonalScribeLogCategory.transcription)
        )

        let activeModelId = await transcriber.activeModelId

        XCTAssertEqual(activeModelId, BuiltInModelCatalog.defaultModelId)
    }

    func testInternalInitializerAcceptsCustomDescriptor() async {
        let descriptor = ModelDescriptor(
            id: "test-model",
            displayName: "Test Model",
            repository: "example/test-model",
            revision: "1234567890123456789012345678901234567890",
            requiredRelativePaths: ["parakeet_vocab.json"],
            approximateSizeBytes: 1,
            engine: .parakeetTDT
        )
        let transcriber = FluidAudioTranscriber(
            inference: StubInferenceClient(),
            descriptor: descriptor
        )

        let activeModelId = await transcriber.activeModelId

        XCTAssertEqual(activeModelId, descriptor.id)
    }
}
