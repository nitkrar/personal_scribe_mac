import AppKit
import XCTest
@testable import PersonalScribeAppKit

@MainActor
final class SettingsWindowControllerWindowTintTests: XCTestCase {
    func testWindowAppearanceIsNilForWarmTint() {
        let defaults = Self.isolatedDefaults()
        WindowTint.warm.persist(to: defaults)

        let controller = makeController(defaults: defaults)
        defer { controller.close() }

        XCTAssertNil(controller.window?.appearance)
    }

    func testWindowAppearanceIsNilForNeutralTint() {
        let defaults = Self.isolatedDefaults()
        WindowTint.neutral.persist(to: defaults)

        let controller = makeController(defaults: defaults)
        defer { controller.close() }

        XCTAssertNil(controller.window?.appearance)
    }

    func testWindowAppearanceIsDarkAquaForDarkTint() {
        let defaults = Self.isolatedDefaults()
        WindowTint.dark.persist(to: defaults)

        let controller = makeController(defaults: defaults)
        defer { controller.close() }

        XCTAssertEqual(controller.window?.appearance?.name, .darkAqua)
    }

    func testWindowAppearanceUpdatesWhenTintChangesViaDefaults() {
        let defaults = Self.isolatedDefaults()
        WindowTint.warm.persist(to: defaults)

        let controller = makeController(defaults: defaults)
        defer { controller.close() }

        XCTAssertNil(controller.window?.appearance)

        WindowTint.dark.persist(to: defaults)
        NotificationCenter.default.post(
            name: UserDefaults.didChangeNotification,
            object: defaults
        )
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))

        XCTAssertEqual(controller.window?.appearance?.name, .darkAqua)
    }

    private func makeController(defaults: UserDefaults) -> SettingsWindowController {
        _ = NSApplication.shared
        return SettingsWindowController(defaults: defaults)
    }

    private static func isolatedDefaults() -> UserDefaults {
        let suiteName = "SettingsWindowControllerWindowTintTests-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            fatalError("Could not create isolated UserDefaults for test")
        }
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
