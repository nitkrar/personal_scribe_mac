import FluidAudio
import XCTest
import PersonalScribeCore

/// Our descriptors' required model bundles must match what FluidAudio loads, or a bump silently breaks "downloaded" state.
final class FluidAudioRequiredFilesTests: XCTestCase {
    private func bundles(_ descriptor: ModelDescriptor) -> Set<String> {
        Set(descriptor.requiredRelativePaths.compactMap { path in
            path.split(separator: "/").first.map(String.init).flatMap { $0.hasSuffix(".mlmodelc") ? $0 : nil }
        })
    }

    func testParakeetDescriptorsMatchFluidAudioRequiredModels() {
        XCTAssertEqual(bundles(BuiltInModelCatalog.parakeetTDT06Bv2), ModelNames.ASR.requiredModels)
        XCTAssertEqual(bundles(BuiltInModelCatalog.parakeetTDT06Bv3), ModelNames.ASR.requiredModelsV3())
        XCTAssertEqual(bundles(BuiltInModelCatalog.parakeetTDTCTC110M), ModelNames.ASR.requiredModelsFused)
    }

    func testParakeetEouDescriptorsMatchFluidAudioRequiredModels() {
        let expected = ModelNames.ParakeetEOU.requiredModels.filter { $0.hasSuffix(".mlmodelc") }
        for descriptor in [BuiltInModelCatalog.parakeetEou160ms, BuiltInModelCatalog.parakeetEou320ms, BuiltInModelCatalog.parakeetEou1280ms] {
            XCTAssertEqual(bundles(descriptor), expected, descriptor.id)
        }
    }
}
