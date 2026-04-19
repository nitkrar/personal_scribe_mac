import XCTest
import SeshatCore
@testable import SeshatTranscription

final class FluidAudioTranscriberRuntimeVariantTests: SeshatTranscriptionFilesystemTestCase {
    func testPrepareLoadsModelsUsingDescriptorRuntimeVariant() async throws {
        let descriptor = BuiltInModelCatalog.parakeetTDTCTC110M
        let modelRoot = try SeshatConfig.directory(for: descriptor)
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
