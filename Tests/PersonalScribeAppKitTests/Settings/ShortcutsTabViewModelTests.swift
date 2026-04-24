import XCTest
import PersonalScribeCore
@testable import PersonalScribeAppKit

@MainActor
final class ShortcutsTabViewModelTests: XCTestCase {
    private let suiteName = "ShortcutsTabViewModelTests"

    private func isolatedDefaults() -> UserDefaults {
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    func testRestoreDefaultResetsToOptSlashAndPersists() {
        let defaults = isolatedDefaults()
        let custom = HotkeyPreference(
            keyCode: 15,
            tapCount: 1,
            modifiers: NSEvent.ModifierFlags.command.union(.shift).rawValue
        )
        custom.persist(to: defaults)

        let viewModel = ShortcutsTabViewModel(defaults: defaults)
        XCTAssertEqual(viewModel.recordingHotkey, custom)

        viewModel.restoreDefault()

        XCTAssertEqual(viewModel.recordingHotkey, .default)
        XCTAssertEqual(HotkeyPreference.resolve(from: defaults), .default)
    }
}
