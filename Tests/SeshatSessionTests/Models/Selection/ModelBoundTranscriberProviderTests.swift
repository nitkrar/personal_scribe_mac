import Foundation
import XCTest
import SeshatCore
import SeshatTranscription
@testable import SeshatSession

final class ModelBoundTranscriberProviderTests: XCTestCase {
    func testTranscriberForDescriptorCachesPerVoiceModelID() {
        let storageLocator = TestStorageLocator(
            baseDirectory: FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
        )
        var factoryCallCount = 0
        let provider = ModelBoundTranscriberProvider(
            storageLocator: storageLocator,
            transcriberFactory: { descriptor in
                factoryCallCount += 1
                return ModelAwareFluidAudioTranscriber(
                    descriptor: descriptor,
                    storageLocator: storageLocator
                )
            }
        )

        let first = provider.transcriber(for: BuiltInModelCatalog.parakeetTDTCTC110M)
        let second = provider.transcriber(for: BuiltInModelCatalog.parakeetTDTCTC110M)

        XCTAssertEqual(factoryCallCount, 1)
        XCTAssertTrue((first as AnyObject) === (second as AnyObject))
    }

    func testTranscriberForDifferentDescriptorsCreatesDistinctInstances() {
        let storageLocator = TestStorageLocator(
            baseDirectory: FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
        )
        var factoryCallCount = 0
        let provider = ModelBoundTranscriberProvider(
            storageLocator: storageLocator,
            transcriberFactory: { descriptor in
                factoryCallCount += 1
                return ModelAwareFluidAudioTranscriber(
                    descriptor: descriptor,
                    storageLocator: storageLocator
                )
            }
        )

        let first = provider.transcriber(for: BuiltInModelCatalog.parakeetTDT06Bv2)
        let second = provider.transcriber(for: BuiltInModelCatalog.parakeetTDTCTC110M)

        XCTAssertEqual(factoryCallCount, 2)
        XCTAssertFalse((first as AnyObject) === (second as AnyObject))
    }
}

private struct TestStorageLocator: StorageLocator {
    let baseDirectory: URL

    func url(for directory: ManagedDirectory) -> URL {
        baseDirectory
            .appendingPathComponent(directory.pathComponent, isDirectory: true)
            .standardizedFileURL
    }

    func ensureDirectoriesExist() throws {}
}
