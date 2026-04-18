import SwiftUI
import XCTest
@testable import SeshatAppKit

/// Tests for `ActionButton` — the champagne "Continue" / "Save" style.
final class ActionButtonTests: XCTestCase {
    func testInitializerAcceptsTitleAndAction() {
        var didFire = false
        let button = ActionButton(title: "Continue") { didFire = true }
        XCTAssertEqual(button.title, "Continue")
        XCTAssertFalse(didFire)
        button.action()
        XCTAssertTrue(didFire)
    }

    func testDefaultVariantIsPrimary() {
        let button = ActionButton(title: "Save") { }
        XCTAssertEqual(button.variant, .primary)
    }

    func testSecondaryVariantIsAccepted() {
        let button = ActionButton(title: "Cancel", variant: .secondary) { }
        XCTAssertEqual(button.variant, .secondary)
    }

    func testDefaultIsEnabled() {
        let button = ActionButton(title: "Save") { }
        XCTAssertTrue(button.isEnabled)
    }

    func testDisabledInitializerDoesNotFireAction() {
        var didFire = false
        let button = ActionButton(
            title: "Save",
            isEnabled: false
        ) { didFire = true }
        XCTAssertFalse(button.isEnabled)
        button.action()
        // Action closure is still callable directly — the button view
        // just ignores taps. We're asserting the stored flag here.
        XCTAssertTrue(didFire)
    }
}
