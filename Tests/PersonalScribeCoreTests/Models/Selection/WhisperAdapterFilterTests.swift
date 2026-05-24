import Foundation
import XCTest
@testable import PersonalScribeCore

final class WhisperAdapterFilterTests: XCTestCase {
    func testResolveDefaultsToBoth() {
        let defaults = isolatedDefaults()

        XCTAssertEqual(WhisperAdapterFilter.resolve(from: defaults), .both)
    }

    func testPersistRoundTripsThroughUserDefaults() {
        let defaults = isolatedDefaults()

        WhisperAdapterFilter.bridge.persist(to: defaults)

        XCTAssertEqual(WhisperAdapterFilter.resolve(from: defaults), .bridge)
    }

    func testFilterOnlyHidesWhisperFamilyDescriptors() {
        let descriptors = [
            BuiltInModelCatalog.whisperKitSmall216MB,
            BuiltInModelCatalog.whisperCppSmallQ51,
            BuiltInModelCatalog.whisperCppStreamingSmallQ51,
            BuiltInModelCatalog.parakeetTDTCTC110M,
        ]

        XCTAssertEqual(
            WhisperAdapterFilter.native.filter(descriptors).map(\.id),
            [
                BuiltInModelCatalog.whisperKitSmall216MB.id,
                BuiltInModelCatalog.parakeetTDTCTC110M.id,
            ]
        )
        XCTAssertEqual(
            WhisperAdapterFilter.bridge.filter(descriptors).map(\.id),
            [
                BuiltInModelCatalog.whisperCppSmallQ51.id,
                BuiltInModelCatalog.whisperCppStreamingSmallQ51.id,
                BuiltInModelCatalog.parakeetTDTCTC110M.id,
            ]
        )
        XCTAssertEqual(
            WhisperAdapterFilter.both.filter(descriptors).map(\.id),
            descriptors.map(\.id)
        )
    }

    private func isolatedDefaults() -> UserDefaults {
        let suiteName = "PersonalScribeTests.WhisperAdapterFilter.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        addTeardownBlock {
            UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        }
        return defaults
    }
}
