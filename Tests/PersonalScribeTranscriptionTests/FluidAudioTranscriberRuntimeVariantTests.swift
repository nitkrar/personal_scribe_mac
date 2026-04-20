import XCTest
import PersonalScribeCore
@testable import PersonalScribeTranscription

final class FluidAudioTranscriberRuntimeVariantTests: PersonalScribeTranscriptionFilesystemTestCase {
    func testPrepareLoadsModelsUsingDescriptorRuntimeVariant() async throws {
        let descriptor = BuiltInModelCatalog.parakeetTDTCTC110M
        let modelRoot = try AppConfig.directory(for: descriptor)
        let inference = StubInferenceClient()
        let transcriber = FluidAudioTranscriber(
            downloader: StubModelDownloader(),
            inference: inference,
            descriptor: descriptor
        )

        try TestModelArtifacts.writeValid(to: modelRoot)
        try await transcriber.prepare()

        let loadedRuntimeVariants = await inference.loadedRuntimeVariants
        XCTAssertEqual(loadedRuntimeVariants, [.parakeetTDTCTC110M])
    }
}
