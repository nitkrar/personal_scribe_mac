import AppKit
import SwiftUI
import XCTest
@testable import PersonalScribeAppKit

@MainActor
final class AboutSubTabTests: XCTestCase {
    func testAboutSubTabCanBeInstantiated() {
        let controller = NSHostingController(rootView: AboutSubTab())
        let view = controller.view

        view.layoutSubtreeIfNeeded()

        XCTAssertNotNil(view)
    }
}
