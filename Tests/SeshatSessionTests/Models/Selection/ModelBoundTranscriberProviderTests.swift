import Foundation
import XCTest
@testable import SeshatCore
import SeshatTranscription
@testable import SeshatSession

final class ModelBoundTranscriberProviderTests: XCTestCase {
    func testTranscriberForDescriptorCachesPerVoiceModelID() {
        let storageLocator = TestStorageLocator(
            baseDirectory: FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
        )
        let factoryCallCount = AtomicIntBox()
        let provider = ModelBoundTranscriberProvider(
            storageLocator: storageLocator,
            transcriberFactory: { descriptor in
                factoryCallCount.increment()
                return ModelAwareFluidAudioTranscriber(
                    descriptor: descriptor,
                    storageLocator: storageLocator
                )
            }
        )

        let first = provider.transcriber(for: BuiltInModelCatalog.parakeetTDTCTC110M)
        let second = provider.transcriber(for: BuiltInModelCatalog.parakeetTDTCTC110M)

        XCTAssertEqual(factoryCallCount.value, 1)
        XCTAssertTrue((first as AnyObject) === (second as AnyObject))
    }

    func testTranscriberForDifferentDescriptorsCreatesDistinctInstances() {
        let storageLocator = TestStorageLocator(
            baseDirectory: FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
        )
        let factoryCallCount = AtomicIntBox()
        let provider = ModelBoundTranscriberProvider(
            storageLocator: storageLocator,
            transcriberFactory: { descriptor in
                factoryCallCount.increment()
                return ModelAwareFluidAudioTranscriber(
                    descriptor: descriptor,
                    storageLocator: storageLocator
                )
            }
        )

        let first = provider.transcriber(for: BuiltInModelCatalog.parakeetTDT06Bv2)
        let second = provider.transcriber(for: BuiltInModelCatalog.parakeetTDTCTC110M)

        XCTAssertEqual(factoryCallCount.value, 2)
        XCTAssertFalse((first as AnyObject) === (second as AnyObject))
    }

    func testDownloadForUnknownDescriptorThrowsDescriptorNotRegistered() async {
        let storageLocator = TestStorageLocator(
            baseDirectory: FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
        )
        let provider = ModelBoundTranscriberProvider(storageLocator: storageLocator)
        let unknownDescriptor = ModelDescriptor(
            id: "custom-model",
            displayName: "Custom",
            repository: "FluidInference/custom-model",
            revision: "custom",
            requiredRelativePaths: ["parakeet_vocab.json"],
            approximateSizeBytes: 1,
            engine: .parakeetTDT
        )

        do {
            try await provider.download(unknownDescriptor) { _ in }
            XCTFail("Expected download to reject an unregistered descriptor")
        } catch let error as ModelSelectionError {
            XCTAssertEqual(error, .descriptorNotRegistered(id: unknownDescriptor.id))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
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

private final class AtomicIntBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: Int = 0

    func increment() {
        lock.lock()
        defer { lock.unlock() }
        _value += 1
    }

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return _value
    }
}
