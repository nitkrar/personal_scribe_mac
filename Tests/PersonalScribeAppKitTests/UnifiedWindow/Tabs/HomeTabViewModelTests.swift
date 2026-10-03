import AppKit
import Foundation
import XCTest
@testable import PersonalScribeAppKit
import PersonalScribeCore

@MainActor
final class HomeTabViewModelTests: XCTestCase {
    func testEmptyStateHotkeyHintDefaultsToConfiguredPreference() {
        let viewModel = makeViewModel(defaults: Self.ephemeralDefaults())

        XCTAssertEqual(viewModel.emptyStateHotkeyHint, HotkeyShortcutFormatter.displayString(for: .default))
    }

    func testEmptyStateHotkeyHintReflectsCustomPreference() {
        let defaults = Self.ephemeralDefaults()
        Self.customHotkey.persist(to: defaults)

        let viewModel = makeViewModel(defaults: defaults)

        XCTAssertEqual(viewModel.emptyStateHotkeyHint, HotkeyShortcutFormatter.displayString(for: Self.customHotkey))
    }

    func testRefreshHotkeyPicksUpChangedBinding() {
        let defaults = Self.ephemeralDefaults()
        let viewModel = makeViewModel(defaults: defaults)
        Self.customHotkey.persist(to: defaults)

        viewModel.refreshHotkey()

        XCTAssertEqual(viewModel.emptyStateHotkeyHint, HotkeyShortcutFormatter.displayString(for: Self.customHotkey))
    }

    // MARK: - Helpers

    /// ⌘⇧Space.
    private static let customHotkey = HotkeyPreference(
        keyCode: 49,
        tapCount: 1,
        modifiers: NSEvent.ModifierFlags.command.union(.shift).rawValue
    )

    private func makeViewModel(defaults: UserDefaults) -> HomeTabViewModel {
        HomeTabViewModel(
            metrics: MetricsSnapshotStore(
                reader: EmptyMetricsReading(),
                logger: PersonalScribeLogger.testing(category: PersonalScribeLogCategory.ui)
            ),
            defaults: defaults
        )
    }

    private static func ephemeralDefaults(function: String = #function) -> UserDefaults {
        let suite = "HomeTabViewModelTests.\(function).\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }
}

private struct EmptyMetricsReading: MetricsReading {
    func loadSnapshot(window: MetricsWindow, recentLimit: Int) async throws -> MetricsSnapshot {
        MetricsSnapshot(
            rollups: .empty(window: window),
            recentTranscriptions: [],
            lastUpdatedAt: window.end,
            lastRefreshReason: .initialLoad
        )
    }

    func recentTranscriptions(limit: Int) async throws -> [TranscriptEntry] { [] }
}
