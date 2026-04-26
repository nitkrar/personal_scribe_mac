import Foundation
import XCTest
@testable import PersonalScribeCore

/// #078.9 — `Parameter<Value>` Codable round-trip.
///
/// Per L22, the on-disk shape distinguishes:
/// - `.setting`: `{"source": "setting", "key": "..."}` (+ companion
///   `settingDefault` to round-trip the in-memory hardcoded default).
/// - `.override`: `{"source": "override", "value": ...}`.
///
/// These tests pin the encoded shape (source field, key/value fields)
/// and the case-preserving round-trip.
final class ParameterCodableTests: XCTestCase {

    func testSettingCaseEncodesSourceAndKey() throws {
        let key = SettingKey<TimeInterval>(
            key: "VadSilenceDurationSeconds",
            default: 5.0
        )
        let parameter = Parameter<TimeInterval>.setting(key)

        let data = try JSONEncoder().encode(parameter)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        XCTAssertEqual(json?["source"] as? String, "setting")
        XCTAssertEqual(json?["key"] as? String, "VadSilenceDurationSeconds")
        XCTAssertNil(
            json?["value"],
            "Setting case must not encode an override value field."
        )
    }

    func testOverrideCaseEncodesSourceAndValue() throws {
        let parameter = Parameter<Bool>.override(true)

        let data = try JSONEncoder().encode(parameter)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        XCTAssertEqual(json?["source"] as? String, "override")
        XCTAssertEqual(json?["value"] as? Bool, true)
        XCTAssertNil(
            json?["key"],
            "Override case must not encode a setting key field."
        )
    }

    func testRoundTripPreservesCase() throws {
        let settingParameter = Parameter<TimeInterval>.setting(
            SettingKey<TimeInterval>(
                key: "VadSilenceDurationSeconds",
                default: 5.0
            )
        )
        let overrideParameter = Parameter<Bool>.override(false)

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let settingRoundTripped = try decoder.decode(
            Parameter<TimeInterval>.self,
            from: encoder.encode(settingParameter)
        )
        let overrideRoundTripped = try decoder.decode(
            Parameter<Bool>.self,
            from: encoder.encode(overrideParameter)
        )

        switch settingRoundTripped {
        case .setting(let key):
            XCTAssertEqual(key.key, "VadSilenceDurationSeconds")
            XCTAssertEqual(key.default, 5.0, accuracy: 0.0001)
        case .override:
            XCTFail("Setting case round-tripped as override")
        }

        switch overrideRoundTripped {
        case .override(let value):
            XCTAssertEqual(value, false)
        case .setting:
            XCTFail("Override case round-tripped as setting")
        }
    }
}
