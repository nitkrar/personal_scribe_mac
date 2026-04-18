import XCTest
@testable import SeshatCore

final class ModelRegistryTests: XCTestCase {
    func testDescriptorLookupRoundTripsDefaultDescriptor() {
        let descriptor = ModelRegistry.parakeetTDT06Bv2

        XCTAssertEqual(ModelRegistry.descriptor(for: descriptor.id), descriptor)
    }

    func testDefaultModelIdMatchesParakeetDescriptor() {
        XCTAssertEqual(ModelRegistry.defaultModelId, "parakeet-tdt-0.6b-v2")
        XCTAssertEqual(ModelRegistry.defaultModelId, ModelRegistry.parakeetTDT06Bv2.id)
    }

    func testResolveURLUsesPinnedRepositoryRevisionAndRelativePath() {
        let url = ModelRegistry.parakeetTDT06Bv2.resolveURL(for: "parakeet_vocab.json")

        XCTAssertEqual(
            url.absoluteString,
            "https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v2-coreml/resolve/ee09c569f73759e6d44c9bd16766f477b2b36d39/parakeet_vocab.json"
        )
    }
}
