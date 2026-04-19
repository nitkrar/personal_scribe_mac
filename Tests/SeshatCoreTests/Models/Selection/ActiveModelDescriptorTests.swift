import Foundation
import XCTest
@testable import SeshatCore

final class ActiveModelDescriptorTests: XCTestCase {
    private func isolatedDefaults() -> UserDefaults {
        let suiteName = "SeshatTests.ActiveModelDescriptor.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        addTeardownBlock {
            UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        }
        return defaults
    }

    func testCodableRoundTripPreservesVoiceAndAISelection() throws {
        let descriptor = ActiveModelDescriptor(
            voiceModel: BuiltInModelCatalog.parakeetTDTCTC110M,
            aiModelID: "gpt-5"
        )

        let encoded = try JSONEncoder().encode(descriptor)
        let decoded = try JSONDecoder().decode(ActiveModelDescriptor.self, from: encoded)

        XCTAssertEqual(decoded, descriptor)
    }

    func testPreferenceRoundTripPersistsCompositeDescriptorAsData() {
        let defaults = isolatedDefaults()
        let preference = Preference<ActiveModelDescriptor>(
            key: "ActiveModelDescriptor",
            default: BuiltInModelCatalog.defaultActiveDescriptor,
            defaults: defaults
        )
        let stored = ActiveModelDescriptor(
            voiceModel: BuiltInModelCatalog.parakeetTDTCTC110M,
            aiModelID: nil
        )

        preference.persist(stored)

        XCTAssertNotNil(defaults.data(forKey: "ActiveModelDescriptor"))
        XCTAssertEqual(preference.resolve(), stored)
    }
}
