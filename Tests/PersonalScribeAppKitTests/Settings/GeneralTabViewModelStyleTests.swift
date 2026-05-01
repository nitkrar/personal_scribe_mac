import XCTest
@testable import PersonalScribeAppKit

/// Tests for the `PillStyle` wiring on `GeneralTabViewModel` — added in
/// mockup-gaps D.1 alongside the new RECORDING WINDOW → Style card.
///
/// Parallel to `GeneralTabViewModelThemeTests` (which covers
/// `WindowTint` + `PillAppearance`); keeping pillStyle assertions in
/// their own file so the Theme tests stay focused on the colour /
/// tint pair and don't balloon past their original scope.
@MainActor
final class GeneralTabViewModelStyleTests: XCTestCase {
    func testInitReadsPillStyleFromDefaults() {
        let defaults = Self.isolatedDefaults()
        PillStyle.mini.persist(to: defaults)

        let viewModel = GeneralTabViewModel(defaults: defaults)

        XCTAssertEqual(viewModel.pillStyle, .mini)
    }

    func testInitFallsBackToClassicWhenDefaultsEmpty() {
        let defaults = Self.isolatedDefaults()

        let viewModel = GeneralTabViewModel(defaults: defaults)

        XCTAssertEqual(viewModel.pillStyle, .classic)
    }

    func testSetPillStylePersistsAndPublishes() {
        let defaults = Self.isolatedDefaults()
        let viewModel = GeneralTabViewModel(defaults: defaults)

        viewModel.setPillStyle(.none)

        XCTAssertEqual(viewModel.pillStyle, .none)
        XCTAssertEqual(defaults.string(forKey: "PillStyle"), "None")
    }

    func testSetPillStyleToMiniPersistsRawValue() {
        let defaults = Self.isolatedDefaults()
        let viewModel = GeneralTabViewModel(defaults: defaults)

        viewModel.setPillStyle(.mini)

        XCTAssertEqual(viewModel.pillStyle, .mini)
        XCTAssertEqual(defaults.string(forKey: "PillStyle"), "Mini")
    }

    func testSetStreamingCardOverflowModePersistsAndPublishes() {
        let defaults = Self.isolatedDefaults()
        let viewModel = GeneralTabViewModel(defaults: defaults)

        viewModel.setStreamingCardOverflowMode(.marquee)

        XCTAssertEqual(viewModel.streamingCardOverflowMode, .marquee)
        XCTAssertEqual(
            StreamingCardOverflowModePreference.resolve(from: defaults),
            .marquee
        )
    }

    private static func isolatedDefaults() -> UserDefaults {
        let suiteName = "GeneralTabViewModelStyleTests-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            fatalError("Could not create isolated UserDefaults for test")
        }
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
