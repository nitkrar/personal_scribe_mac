import XCTest
@testable import PersonalScribeAppKit

/// Tests for `UnifiedWindowModel` — the routing state for the unified
/// NavigationSplitView window (M3.1 scaffold).
@MainActor
final class UnifiedWindowModelTests: XCTestCase {
    func testDefaultActiveTabIsHome() {
        let model = UnifiedWindowModel()
        XCTAssertEqual(model.activeTab, .home)
    }

    func testSetActiveTabUpdatesPublishedValue() {
        let model = UnifiedWindowModel()
        model.setActiveTab(.transcriptions)
        XCTAssertEqual(model.activeTab, .transcriptions)
    }

    func testSetActiveTabAcceptsEveryCase() {
        let model = UnifiedWindowModel()
        for tab in AppTab.allCases {
            model.setActiveTab(tab)
            XCTAssertEqual(model.activeTab, tab)
        }
    }

    func testInitWithExplicitInitialTab() {
        let model = UnifiedWindowModel(initialTab: .settings)
        XCTAssertEqual(model.activeTab, .settings)
    }

    // MARK: - AppTab contract

    func testAppTabCasesInOrder() {
        XCTAssertEqual(
            AppTab.allCases,
            [.home, .transcriptions, .modes, .settings, .about]
        )
    }

    func testAppTabRawValuesAreStable() {
        XCTAssertEqual(AppTab.home.rawValue, "Home")
        XCTAssertEqual(AppTab.transcriptions.rawValue, "Transcriptions")
        XCTAssertEqual(AppTab.modes.rawValue, "Modes")
        XCTAssertEqual(AppTab.settings.rawValue, "Settings")
        XCTAssertEqual(AppTab.about.rawValue, "About")
    }

    func testAppTabSystemImageNames() {
        XCTAssertEqual(AppTab.home.systemImageName, "house.fill")
        XCTAssertEqual(AppTab.transcriptions.systemImageName, "waveform")
        XCTAssertEqual(AppTab.modes.systemImageName, "square.grid.2x2")
        XCTAssertEqual(AppTab.settings.systemImageName, "gearshape")
        XCTAssertEqual(AppTab.about.systemImageName, "info.circle")
    }

    /// About is rendered as a clickable footer row (next to the
    /// Microphone footer), not as a regular sidebar-list tab. Keep
    /// the two lists semantically distinct so SidebarListView can
    /// iterate `sidebarListCases` without accidentally including About.
    func testSidebarListCasesExcludesAbout() {
        XCTAssertEqual(
            AppTab.sidebarListCases,
            [.home, .transcriptions, .modes, .settings]
        )
        XCTAssertFalse(AppTab.sidebarListCases.contains(.about))
    }
}
