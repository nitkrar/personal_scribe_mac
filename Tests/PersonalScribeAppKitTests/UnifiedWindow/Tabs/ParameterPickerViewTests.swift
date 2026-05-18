import XCTest
import PersonalScribeCore
@testable import PersonalScribeAppKit

@MainActor
final class ParameterPickerViewTests: XCTestCase {
    func testBoolOverrideLabelsDropForcePrefix() {
        XCTAssertEqual(ParameterPickerView.overrideLabel(for: true), "On")
        XCTAssertEqual(ParameterPickerView.overrideLabel(for: false), "Off")
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
