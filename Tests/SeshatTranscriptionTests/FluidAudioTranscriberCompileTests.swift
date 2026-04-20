import XCTest
@testable import SeshatCore
@testable import SeshatTranscription

final class FluidAudioTranscriberCompileTests: XCTestCase {
    func testFluidAudioTranscriberConformsToTranscribing() {
        let transcriber: any Transcribing = FluidAudioTranscriber(
            logger: SeshatLogger(category: SeshatLogCategory.transcription)
        )

        XCTAssertNotNil(transcriber)
    }

    func testDefaultInitializerUsesRegistryDefaultModelId() async {
        let transcriber = FluidAudioTranscriber(
            logger: SeshatLogger(category: SeshatLogCategory.transcription)
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
            downloader: StubModelDownloader(),
            inference: StubInferenceClient(),
            descriptor: descriptor
        )

        let activeModelId = await transcriber.activeModelId

        XCTAssertEqual(activeModelId, descriptor.id)
    }
}
