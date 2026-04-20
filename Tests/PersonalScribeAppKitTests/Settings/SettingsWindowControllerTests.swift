import AppKit
import XCTest
@testable import PersonalScribeAppKit

@MainActor
final class SettingsWindowControllerTests: XCTestCase {
    func testShowWindowOpensControllerWindowOnceAndReusesIt() {
        _ = NSApplication.shared
        let controller = SettingsWindowController()

        controller.showWindow(nil)
        let firstWindow = controller.window

        controller.showWindow(nil)
        let secondWindow = controller.window

        XCTAssertNotNil(firstWindow)
        XCTAssertTrue(firstWindow === secondWindow)

        controller.close()
    }
}
