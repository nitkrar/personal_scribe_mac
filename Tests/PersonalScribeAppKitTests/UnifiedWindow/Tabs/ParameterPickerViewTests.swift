import XCTest
import PersonalScribeCore
@testable import PersonalScribeAppKit

@MainActor
final class ParameterPickerViewTests: XCTestCase {
    func testBoolDefaultLabelsDropLivePrefix() {
        XCTAssertEqual(ParameterPickerView.defaultLabel(for: true), "Default (On)")
        XCTAssertEqual(ParameterPickerView.defaultLabel(for: false), "Default (Off)")
    }

    func testBoolOverrideLabelsDropForcePrefix() {
        XCTAssertEqual(ParameterPickerView.overrideLabel(for: true), "On")
        XCTAssertEqual(ParameterPickerView.overrideLabel(for: false), "Off")
    }

    func testSensitivityDefaultLabelsDropLivePrefix() {
        XCTAssertEqual(
            SensitivityParameterPickerView.defaultLabel(for: .relaxed),
            "Default (Relaxed)"
        )
        XCTAssertEqual(
            SensitivityParameterPickerView.defaultLabel(for: .balanced),
            "Default (Balanced)"
        )
        XCTAssertEqual(
            SensitivityParameterPickerView.defaultLabel(for: .strict),
            "Default (Strict)"
        )
    }

    func testSensitivityOverrideLabelsDropForcePrefix() {
        XCTAssertEqual(
            SensitivityParameterPickerView.overrideLabel(for: .relaxed),
            "Relaxed"
        )
        XCTAssertEqual(
            SensitivityParameterPickerView.overrideLabel(for: .balanced),
            "Balanced"
        )
        XCTAssertEqual(
            SensitivityParameterPickerView.overrideLabel(for: .strict),
            "Strict"
        )
    }
}
