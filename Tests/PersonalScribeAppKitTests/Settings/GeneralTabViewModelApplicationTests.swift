import XCTest
@testable import PersonalScribeAppKit

/// Tests for the APPLICATION section's view-model wiring on
/// `GeneralTabViewModel` — added in mockup-gaps D.2.
///
/// Covers the `showInDock` preference's init / setter / persistence.
/// The setter's activation-policy side effect (`NSApp.setActivationPolicy`)
/// is NOT asserted here: `NSApp` isn't test-safe in isolation, and a
/// dependency-injection seam for the activation-policy call would
/// balloon the surface area beyond what this gap closes. The setter's
/// persistence + published state is what this test locks in; the
/// runtime Dock add/remove is covered in the manual-verification
/// runbook.
@MainActor
final class GeneralTabViewModelApplicationTests: XCTestCase {
    func testInitReadsShowInDockFromDefaults() {
        let defaults = Self.isolatedDefaults()
        ShowInDockPreference.persist(false, to: defaults)

        let viewModel = GeneralTabViewModel(defaults: defaults)

        XCTAssertFalse(viewModel.showInDock)
    }

    func testInitFallsBackToTrueWhenDefaultsEmpty() {
        let defaults = Self.isolatedDefaults()

        let viewModel = GeneralTabViewModel(defaults: defaults)

        XCTAssertTrue(viewModel.showInDock)
    }

    func testSetShowInDockPersistsAndPublishes() {
        let defaults = Self.isolatedDefaults()
        let viewModel = GeneralTabViewModel(defaults: defaults)

        viewModel.setShowInDock(false)

        XCTAssertFalse(viewModel.showInDock)
        XCTAssertEqual(
            defaults.object(forKey: "ShowInDock") as? Bool,
            false
        )
    }

    func testSetShowInDockTrueRoundTrips() {
        let defaults = Self.isolatedDefaults()
        ShowInDockPreference.persist(false, to: defaults)
        let viewModel = GeneralTabViewModel(defaults: defaults)
        XCTAssertFalse(viewModel.showInDock)

        viewModel.setShowInDock(true)

        XCTAssertTrue(viewModel.showInDock)
        XCTAssertEqual(
            defaults.object(forKey: "ShowInDock") as? Bool,
            true
        )
    }

    private static func isolatedDefaults() -> UserDefaults {
        let suiteName = "GeneralTabViewModelApplicationTests-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            fatalError("Could not create isolated UserDefaults for test")
        }
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
