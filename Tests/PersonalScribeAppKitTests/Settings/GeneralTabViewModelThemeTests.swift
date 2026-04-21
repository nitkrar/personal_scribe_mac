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

    // MARK: - AppTheme (mockup-gaps G.4)

    func testAppThemeDefaultIsLight() {
        let defaults = Self.isolatedDefaults()

        let viewModel = GeneralTabViewModel(defaults: defaults)

        XCTAssertEqual(viewModel.appTheme, .light)
    }

    func testInitReadsAppThemeFromDefaults() {
        let defaults = Self.isolatedDefaults()
        AppTheme.dark.persist(to: defaults)

        let viewModel = GeneralTabViewModel(defaults: defaults)

        XCTAssertEqual(viewModel.appTheme, .dark)
    }

    func testSetAppThemePersistsAndPublishes() {
        let defaults = Self.isolatedDefaults()
        let viewModel = GeneralTabViewModel(defaults: defaults)

        viewModel.setAppTheme(.dark)

        XCTAssertEqual(viewModel.appTheme, .dark)
        XCTAssertEqual(defaults.string(forKey: "AppTheme"), "Dark")
    }

    /// P5 invariant: setting `AppTheme` must NOT mutate
    /// `pillAppearance`. Pill appearance is independent of the master
    /// theme per user decision (2026-04-21).
    func testSetAppThemeDoesNotMutatePillAppearance() {
        let defaults = Self.isolatedDefaults()
        PillAppearance.light.persist(to: defaults)
        let viewModel = GeneralTabViewModel(defaults: defaults)
        XCTAssertEqual(viewModel.pillAppearance, .light)

        viewModel.setAppTheme(.dark)

        XCTAssertEqual(viewModel.pillAppearance, .light)
        XCTAssertEqual(defaults.string(forKey: "PillAppearance"), "Light")
    }

    /// Setting `AppTheme` must NOT mutate `windowTint`. Tint is just
    /// hidden from the UI when the effective scheme is dark; the
    /// persisted value is preserved so flipping back to Light restores
    /// the prior tint flavor.
    func testSetAppThemeDoesNotMutateWindowTint() {
        let defaults = Self.isolatedDefaults()
        WindowTint.neutral.persist(to: defaults)
        let viewModel = GeneralTabViewModel(defaults: defaults)
        XCTAssertEqual(viewModel.windowTint, .neutral)

        viewModel.setAppTheme(.dark)

        XCTAssertEqual(viewModel.windowTint, .neutral)
        XCTAssertEqual(defaults.string(forKey: "WindowTint"), "Neutral")
    }

    // MARK: - showsTintPicker (effective-scheme matrix)

    func testShowsTintPickerTrueWhenAppThemeLightAndSystemLight() {
        let viewModel = Self.makeViewModel(appTheme: .light, systemIsDark: false)
        XCTAssertTrue(viewModel.showsTintPicker)
    }

    func testShowsTintPickerTrueWhenAppThemeLightAndSystemDark() {
        let viewModel = Self.makeViewModel(appTheme: .light, systemIsDark: true)
        XCTAssertTrue(viewModel.showsTintPicker)
    }

    func testShowsTintPickerFalseWhenAppThemeDarkAndSystemLight() {
        let viewModel = Self.makeViewModel(appTheme: .dark, systemIsDark: false)
        XCTAssertFalse(viewModel.showsTintPicker)
    }

    func testShowsTintPickerFalseWhenAppThemeDarkAndSystemDark() {
        let viewModel = Self.makeViewModel(appTheme: .dark, systemIsDark: true)
        XCTAssertFalse(viewModel.showsTintPicker)
    }

    func testShowsTintPickerTrueWhenAppThemeSystemAndSystemLight() {
        let viewModel = Self.makeViewModel(appTheme: .system, systemIsDark: false)
        XCTAssertTrue(viewModel.showsTintPicker)
    }

    func testShowsTintPickerFalseWhenAppThemeSystemAndSystemDark() {
        let viewModel = Self.makeViewModel(appTheme: .system, systemIsDark: true)
        XCTAssertFalse(viewModel.showsTintPicker)
    }

    func testShowsTintPickerReactsToSetAppTheme() {
        let viewModel = Self.makeViewModel(appTheme: .light, systemIsDark: false)
        XCTAssertTrue(viewModel.showsTintPicker)

        viewModel.setAppTheme(.dark)
        XCTAssertFalse(viewModel.showsTintPicker)

        viewModel.setAppTheme(.light)
        XCTAssertTrue(viewModel.showsTintPicker)
    }

    // MARK: - Helpers

    private static func makeViewModel(
        appTheme: AppTheme,
        systemIsDark: Bool
    ) -> GeneralTabViewModel {
        let defaults = isolatedDefaults()
        appTheme.persist(to: defaults)
        return GeneralTabViewModel(
            defaults: defaults,
            systemIsDarkProvider: { systemIsDark }
        )
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
