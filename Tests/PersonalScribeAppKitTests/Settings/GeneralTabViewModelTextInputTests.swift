import XCTest
@testable import PersonalScribeAppKit

/// Tests for the TEXT INPUT section's view-model wiring on
/// `GeneralTabViewModel` — added in mockup-gaps D.3.
///
/// Covers the new `pasteEnabled` master toggle's init + setter +
/// persistence. `pasteMode` binding isn't re-tested here (already
/// covered implicitly by the existing view-model init and not
/// changed by D.3 — the picker was only MOVED from the Behavior
/// card into the new Text Input card).
@MainActor
final class GeneralTabViewModelTextInputTests: XCTestCase {
    func testInitReadsPasteEnabledFromDefaults() {
        let defaults = Self.isolatedDefaults()
        PasteEnabledPreference.persist(false, to: defaults)

        let viewModel = GeneralTabViewModel(defaults: defaults)

        XCTAssertFalse(viewModel.pasteEnabled)
    }

    func testInitFallsBackToTrueWhenDefaultsEmpty() {
        let defaults = Self.isolatedDefaults()

        let viewModel = GeneralTabViewModel(defaults: defaults)

        XCTAssertTrue(viewModel.pasteEnabled)
    }

    func testSetPasteEnabledPersistsAndPublishes() {
        let defaults = Self.isolatedDefaults()
        let viewModel = GeneralTabViewModel(defaults: defaults)

        viewModel.setPasteEnabled(false)

        XCTAssertFalse(viewModel.pasteEnabled)
        XCTAssertEqual(
            defaults.object(forKey: "PasteEnabled") as? Bool,
            false
        )
    }

    func testSetPasteEnabledTrueRoundTrips() {
        let defaults = Self.isolatedDefaults()
        PasteEnabledPreference.persist(false, to: defaults)
        let viewModel = GeneralTabViewModel(defaults: defaults)
        XCTAssertFalse(viewModel.pasteEnabled)

        viewModel.setPasteEnabled(true)

        XCTAssertTrue(viewModel.pasteEnabled)
        XCTAssertEqual(
            defaults.object(forKey: "PasteEnabled") as? Bool,
            true
        )
    }

    private static func isolatedDefaults() -> UserDefaults {
        let suiteName = "GeneralTabViewModelTextInputTests-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            fatalError("Could not create isolated UserDefaults for test")
        }
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
