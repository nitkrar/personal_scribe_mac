import XCTest
@testable import PersonalScribeAppKit

@MainActor
final class SettingsSubTabTests: XCTestCase {
    func testCasesInOrder() {
        XCTAssertEqual(
            SettingsSubTab.allCases,
            [.general, .aiModels, .shortcuts, .advanced, .permissions, .about]
        )
    }

    func testRawValuesAreStable() {
        XCTAssertEqual(SettingsSubTab.general.rawValue, "General")
        XCTAssertEqual(SettingsSubTab.aiModels.rawValue, "AI Models")
        XCTAssertEqual(SettingsSubTab.shortcuts.rawValue, "Shortcuts")
        XCTAssertEqual(SettingsSubTab.advanced.rawValue, "Advanced")
        XCTAssertEqual(SettingsSubTab.permissions.rawValue, "Permissions")
        XCTAssertEqual(SettingsSubTab.about.rawValue, "About")
    }

    func testIdMatchesRawValue() {
        for subTab in SettingsSubTab.allCases {
            XCTAssertEqual(subTab.id, subTab.rawValue)
        }
    }

    func testAllCasesAreIdentifiable() {
        let ids = SettingsSubTab.allCases.map(\.id)
        XCTAssertEqual(
            ids,
            ["General", "AI Models", "Shortcuts", "Advanced", "Permissions", "About"]
        )
        XCTAssertEqual(Set(ids).count, SettingsSubTab.allCases.count)
    }
}
