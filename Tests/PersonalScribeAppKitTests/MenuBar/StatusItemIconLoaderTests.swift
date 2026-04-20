import AppKit
import XCTest
@testable import PersonalScribeAppKit

/// Verifies the menu-bar icon actually loads from `Bundle.module`.
///
/// Regression coverage for the packaged-app bug where
/// `NSImage(named: "StatusBarIcon")` returned `nil` and the status
/// item fell back to the "S" text glyph. If this test fails, either
/// the asset catalog was stripped from the PersonalScribeAppKit resources or
/// `Bundle.module` no longer points at the right bundle — both of
/// which would reproduce the runtime bug.
@MainActor
final class StatusItemIconLoaderTests: XCTestCase {
    func testLoadStatusBarIconReturnsNonNilImage() {
        let image = StatusItemIconLoader.loadStatusBarIcon()
        XCTAssertNotNil(
            image,
            "StatusBarIcon must load from Bundle.module; otherwise the menu-bar status item falls back to the 'S' text glyph."
        )
    }

    func testLoadStatusBarIconMarksImageAsTemplate() {
        guard let image = StatusItemIconLoader.loadStatusBarIcon() else {
            XCTFail("StatusBarIcon failed to load — covered by testLoadStatusBarIconReturnsNonNilImage")
            return
        }
        XCTAssertTrue(
            image.isTemplate,
            "StatusBarIcon should be marked as template so AppKit tints it for light/dark menu bars."
        )
    }
}
