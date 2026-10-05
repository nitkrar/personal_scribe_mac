import AppKit
import Foundation
import XCTest
@testable import PersonalScribeAppKit
import PersonalScribeCore

@MainActor
final class HomeTabViewModelTests: XCTestCase {
    func testChecklistMarksAchievementsAndKeepsThemAfterSignalsDisappear() {
        let defaults = Self.ephemeralDefaults()
        let checklist = HomeChecklistState(defaults: defaults)

        checklist.update(
            hasTranscript: true,
            hasCustomHotkey: true,
            hasCustomMode: true
        )
        checklist.update(
            hasTranscript: false,
            hasCustomHotkey: false,
            hasCustomMode: false
        )

        XCTAssertEqual(checklist.completedItems, Set(HomeChecklistItem.allCases))
        XCTAssertEqual(checklist.completedCount, 3)
        XCTAssertTrue(checklist.isComplete)
    }

    func testChecklistRestoresEachPersistedAchievement() {
        let defaults = Self.ephemeralDefaults()
        var checklist = HomeChecklistState(defaults: defaults)
        checklist.update(
            hasTranscript: true,
            hasCustomHotkey: false,
            hasCustomMode: true
        )

        checklist = HomeChecklistState(defaults: defaults)

        XCTAssertEqual(checklist.completedItems, [.startRecording, .createMode])
        XCTAssertEqual(checklist.completedCount, 2)
    }

    func testChecklistDismissesOnlyWhenCompleteAndRestoresDismissal() {
        let defaults = Self.ephemeralDefaults()
        var checklist = HomeChecklistState(defaults: defaults)

        checklist.dismiss()
        XCTAssertFalse(checklist.isDismissed)

        checklist.update(
            hasTranscript: true,
            hasCustomHotkey: true,
            hasCustomMode: true
        )
        checklist.dismiss()
        XCTAssertTrue(checklist.isDismissed)

        checklist = HomeChecklistState(defaults: defaults)
        XCTAssertTrue(checklist.isDismissed)
        XCTAssertFalse(checklist.isVisible)
    }

    func testRefreshChecklistUsesRecentHistoryHotkeyAndCustomModeSignals() {
        let defaults = Self.ephemeralDefaults()
        Self.customHotkey.persist(to: defaults)
        let metrics = MetricsSnapshotStore(
            reader: EmptyMetricsReading(),
            defaults: defaults,
            logger: PersonalScribeLogger.testing(category: PersonalScribeLogCategory.ui)
        )
        let viewModel = HomeTabViewModel(
            metrics: metrics,
            defaults: defaults,
            hasCustomModes: { true }
        )

        viewModel.refreshChecklist()

        XCTAssertEqual(
            viewModel.checklist.completedItems,
            [.customizeShortcut, .createMode]
        )
    }

    func testChecklistActionsRouteShortcutAndModeRows() {
        var destinations: [AppTab] = []
        let viewModel = HomeTabViewModel(
            metrics: MetricsSnapshotStore(
                reader: EmptyMetricsReading(),
                logger: PersonalScribeLogger.testing(category: PersonalScribeLogCategory.ui)
            ),
            openShortcuts: { destinations.append(.settings) },
            openModes: { destinations.append(.modes) }
        )

        viewModel.performChecklistAction(for: .startRecording)
        viewModel.performChecklistAction(for: .customizeShortcut)
        viewModel.performChecklistAction(for: .createMode)

        XCTAssertEqual(destinations, [.settings, .modes])
    }

    func testTimeSavedFormatterUsesHourAndMinuteUnits() {
        XCTAssertEqual(HomeTab.timeSavedText(minutes: 0), "0m")
        XCTAssertEqual(HomeTab.timeSavedText(minutes: 42), "42m")
        XCTAssertEqual(HomeTab.timeSavedText(minutes: 222), "3h 42m")
    }

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
