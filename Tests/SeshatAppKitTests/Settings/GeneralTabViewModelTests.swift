import XCTest
@testable import SeshatAppKit

@MainActor
final class GeneralTabViewModelTests: XCTestCase {
    private let suiteName = "GeneralTabViewModelTests"

    private func isolatedDefaults() -> UserDefaults {
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    func test_applyVisibilityConfig_rejectsBothHidden() {
        let defaults = isolatedDefaults()
        var menuBarVisible = true
        let viewModel = GeneralTabViewModel(
            defaults: defaults,
            menuBarVisibilityProvider: { menuBarVisible },
            menuBarVisibilitySetter: { menuBarVisible = $0 }
        )

        let conflict = viewModel.applyVisibilityConfig(
            .init(
                pillVisibilityMode: .hidden,
                isMenuBarVisible: false
            )
        )

        XCTAssertEqual(conflict, .conflict)
        XCTAssertEqual(viewModel.visibilityError, .conflict)
        XCTAssertEqual(viewModel.pillVisibilityMode, .autoShow)
        XCTAssertTrue(viewModel.isMenuBarVisible)
        XCTAssertEqual(PillVisibilityMode.resolve(from: defaults), .autoShow)
        XCTAssertTrue(menuBarVisible)

        let hidePillOnly = viewModel.applyVisibilityConfig(
            .init(
                pillVisibilityMode: .hidden,
                isMenuBarVisible: true
            )
        )

        XCTAssertNil(hidePillOnly)
        XCTAssertNil(viewModel.visibilityError)
        XCTAssertEqual(viewModel.pillVisibilityMode, .hidden)
        XCTAssertTrue(viewModel.isMenuBarVisible)
        XCTAssertEqual(PillVisibilityMode.resolve(from: defaults), .hidden)
        XCTAssertTrue(menuBarVisible)

        let hideMenuOnly = viewModel.applyVisibilityConfig(
            .init(
                pillVisibilityMode: .alwaysOn,
                isMenuBarVisible: false
            )
        )

        XCTAssertNil(hideMenuOnly)
        XCTAssertNil(viewModel.visibilityError)
        XCTAssertEqual(viewModel.pillVisibilityMode, .alwaysOn)
        XCTAssertFalse(viewModel.isMenuBarVisible)
        XCTAssertEqual(PillVisibilityMode.resolve(from: defaults), .alwaysOn)
        XCTAssertFalse(menuBarVisible)
    }
}
