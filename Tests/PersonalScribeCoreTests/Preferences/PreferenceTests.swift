import Foundation
import SwiftUI
import XCTest
@testable import PersonalScribeCore

private enum TestPreferenceEnum: String, Codable, Sendable {
    case alpha
    case beta
}

private struct TestPreferenceStruct: Codable, Sendable, Equatable {
    let keyCode: UInt16
    let tapCount: Int
}

final class PreferenceTests: XCTestCase {
    private func isolatedDefaults() -> UserDefaults {
        let suiteName = "SeshatTestsPreference.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        addTeardownBlock {
            UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        }
        return defaults
    }

    func testResolveReturnsDefaultWhenKeyIsAbsent() {
        let defaults = isolatedDefaults()
        let preference = Preference<TestPreferenceEnum>(
            key: "MissingPreference",
            default: .alpha,
            defaults: defaults
        )

        XCTAssertEqual(preference.resolve(), .alpha)
    }

    func testResolveReturnsDefaultWhenPersistedRawValueIsUnsupported() {
        let defaults = isolatedDefaults()
        defaults.set("gamma", forKey: "EnumPreference")
        let preference = Preference<TestPreferenceEnum>(
            key: "EnumPreference",
            default: .alpha,
            defaults: defaults
        )

        XCTAssertEqual(preference.resolve(), .alpha)
    }

    func testResolveReturnsDefaultWhenPersistedScalarHasInvalidType() {
        let defaults = isolatedDefaults()
        defaults.set("soon", forKey: "DelayPreference")
        let preference = Preference<Double>(
            key: "DelayPreference",
            default: 0.5,
            defaults: defaults
        )

        XCTAssertEqual(preference.resolve(), 0.5, accuracy: 0.0001)
    }

    func testResolveReturnsDefaultWhenPersistedStructHasInvalidShape() {
        let defaults = isolatedDefaults()
        defaults.set("legacy", forKey: "StructPreference")
        let preference = Preference<TestPreferenceStruct>(
            key: "StructPreference",
            default: TestPreferenceStruct(keyCode: 61, tapCount: 2),
            defaults: defaults
        )

        XCTAssertEqual(preference.resolve(), TestPreferenceStruct(keyCode: 61, tapCount: 2))
    }

    func testPersistRoundTripsRawValueEnumsUsingScalarStorage() {
        let defaults = isolatedDefaults()
        let preference = Preference<TestPreferenceEnum>(
            key: "EnumPreference",
            default: .alpha,
            defaults: defaults
        )

        preference.persist(.beta)

        XCTAssertEqual(defaults.string(forKey: "EnumPreference"), "beta")
        XCTAssertEqual(preference.resolve(), .beta)
    }

    func testPersistRoundTripsScalarNumericValuesUsingNumberStorage() {
        let defaults = isolatedDefaults()
        let preference = Preference<Double>(
            key: "DelayPreference",
            default: 0.5,
            defaults: defaults
        )

        preference.persist(1.7)

        XCTAssertEqual(defaults.double(forKey: "DelayPreference"), 1.7, accuracy: 0.0001)
        XCTAssertEqual(preference.resolve(), 1.7, accuracy: 0.0001)
    }

    func testPersistRoundTripsStructsUsingDataStorage() {
        let defaults = isolatedDefaults()
        let preference = Preference<TestPreferenceStruct>(
            key: "StructPreference",
            default: TestPreferenceStruct(keyCode: 61, tapCount: 2),
            defaults: defaults
        )
        let storedValue = TestPreferenceStruct(keyCode: 49, tapCount: 1)

        preference.persist(storedValue)

        XCTAssertNotNil(defaults.data(forKey: "StructPreference"))
        XCTAssertEqual(preference.resolve(), storedValue)
    }

    @MainActor
    func testBindingReadsAndWritesThroughInjectedDefaults() {
        let defaults = isolatedDefaults()
        let preference = Preference<TestPreferenceEnum>(
            key: "BindingPreference",
            default: .alpha,
            defaults: defaults
        )
        let binding = preference.binding()

        XCTAssertEqual(binding.wrappedValue, .alpha)

        binding.wrappedValue = .beta

        XCTAssertEqual(defaults.string(forKey: "BindingPreference"), "beta")
        XCTAssertEqual(preference.resolve(), .beta)

        defaults.set("alpha", forKey: "BindingPreference")

        XCTAssertEqual(binding.wrappedValue, .alpha)
    }

    func testIsolatedSuitesDoNotLeakValuesBetweenDefaultsInstances() {
        let firstDefaults = isolatedDefaults()
        let secondDefaults = isolatedDefaults()
        let firstPreference = Preference<TestPreferenceEnum>(
            key: "SharedPreferenceKey",
            default: .alpha,
            defaults: firstDefaults
        )
        let secondPreference = Preference<TestPreferenceEnum>(
            key: "SharedPreferenceKey",
            default: .alpha,
            defaults: secondDefaults
        )

        firstPreference.persist(.beta)

        XCTAssertEqual(firstPreference.resolve(), .beta)
        XCTAssertEqual(secondPreference.resolve(), .alpha)
    }
}
