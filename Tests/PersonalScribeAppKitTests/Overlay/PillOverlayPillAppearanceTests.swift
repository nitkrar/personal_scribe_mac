import AppKit
import XCTest
@testable import PersonalScribeAppKit

@MainActor
final class PillOverlayPillAppearanceTests: XCTestCase {
    func testPanelAppearanceIsDarkAquaForDefaultDarkCase() {
        let defaults = isolatedDefaults()

        let panel = makePanel(defaults: defaults)

        XCTAssertEqual(panel.appearance?.name, .darkAqua)
    }

    func testPanelAppearanceIsAquaForLightCase() {
        let defaults = isolatedDefaults()
        PillAppearance.light.persist(to: defaults)

        let panel = makePanel(defaults: defaults)

        XCTAssertEqual(panel.appearance?.name, .aqua)
    }

    func testPanelAppearanceIsNilForSystemCase() {
        let defaults = isolatedDefaults()
        PillAppearance.system.persist(to: defaults)

        let panel = makePanel(defaults: defaults)

        XCTAssertNil(panel.appearance)
    }

    func testPanelAppearanceUpdatesWhenPillAppearanceChanges() {
        let defaults = isolatedDefaults()
        PillAppearance.dark.persist(to: defaults)
        let panel = makePanel(defaults: defaults)

        PillAppearance.light.persist(to: defaults)
        NotificationCenter.default.post(
            name: UserDefaults.didChangeNotification,
            object: defaults
        )
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))

        XCTAssertEqual(panel.appearance?.name, .aqua)
    }

    private func makePanel(defaults: UserDefaults) -> DraggablePanel {
        DraggablePanel(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 60),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false,
            defaults: defaults
        )
    }

    private func isolatedDefaults() -> UserDefaults {
        let suiteName = "PillOverlayPillAppearanceTests-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            fatalError("Could not create isolated UserDefaults for test")
        }
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
