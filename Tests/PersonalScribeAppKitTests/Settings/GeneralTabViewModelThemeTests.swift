import XCTest
@testable import PersonalScribeAppKit

@MainActor
final class GeneralTabViewModelThemeTests: XCTestCase {
    func testInitReadsWindowTintFromDefaults() {
        let defaults = Self.isolatedDefaults()
        WindowTint.neutral.persist(to: defaults)

        let viewModel = GeneralTabViewModel(defaults: defaults)

        XCTAssertEqual(viewModel.windowTint, .neutral)
    }

    func testInitFallsBackToWarmWhenDefaultsEmpty() {
        let defaults = Self.isolatedDefaults()

        let viewModel = GeneralTabViewModel(defaults: defaults)

        XCTAssertEqual(viewModel.windowTint, .warm)
    }

    func testSetWindowTintPersistsAndPublishes() {
        let defaults = Self.isolatedDefaults()
        let viewModel = GeneralTabViewModel(defaults: defaults)

        viewModel.setWindowTint(.neutral)

        XCTAssertEqual(viewModel.windowTint, .neutral)
        XCTAssertEqual(defaults.string(forKey: "WindowTint"), "Neutral")
    }

    func testInitReadsPillAppearanceFromDefaults() {
        let defaults = Self.isolatedDefaults()
        PillAppearance.system.persist(to: defaults)

        let viewModel = GeneralTabViewModel(defaults: defaults)

        XCTAssertEqual(viewModel.pillAppearance, .system)
    }

    func testInitFallsBackToDarkWhenDefaultsEmpty() {
        let defaults = Self.isolatedDefaults()

        let viewModel = GeneralTabViewModel(defaults: defaults)

        XCTAssertEqual(viewModel.pillAppearance, .dark)
    }

    func testSetPillAppearancePersistsAndPublishes() {
        let defaults = Self.isolatedDefaults()
        let viewModel = GeneralTabViewModel(defaults: defaults)

        viewModel.setPillAppearance(.light)

        XCTAssertEqual(viewModel.pillAppearance, .light)
        XCTAssertEqual(defaults.string(forKey: "PillAppearance"), "Light")
    }

    private static func isolatedDefaults() -> UserDefaults {
        let suiteName = "GeneralTabViewModelThemeTests-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            fatalError("Could not create isolated UserDefaults for test")
        }
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
