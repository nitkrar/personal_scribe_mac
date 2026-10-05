import AppKit
import Combine
import Foundation
import XCTest
@testable import PersonalScribeAppKit
import PersonalScribeCore

@MainActor
final class HomeTabViewModelTests: XCTestCase {
    func testChecklistRestoresPendingSetupAchievementsAndIgnoresLegacyRecordingTick() {
        let defaults = Self.ephemeralDefaults()
        defaults.set(true, forKey: "HomeChecklistStartRecordingComplete")
        defaults.set(true, forKey: "HomeChecklistCreateModeComplete")

        let checklist = HomeChecklistState(defaults: defaults)

        XCTAssertEqual(checklist.completedItems, [.createMode])
        XCTAssertEqual(checklist.pendingItems, [.customizeShortcut])
        XCTAssertTrue(checklist.isVisible)
    }

    func testChecklistDismissesAtAnyTimeAndRestoresDismissal() {
        let defaults = Self.ephemeralDefaults()
        var checklist = HomeChecklistState(defaults: defaults)

        checklist.dismiss()
        XCTAssertTrue(checklist.isDismissed)
        XCTAssertFalse(checklist.isVisible)

        checklist = HomeChecklistState(defaults: defaults)
        XCTAssertTrue(checklist.isDismissed)
        XCTAssertFalse(checklist.isVisible)
    }

    func testChecklistManualCompletionPersistsAndHidesCardWhenNothingIsPending() {
        let defaults = Self.ephemeralDefaults()
        let checklist = HomeChecklistState(defaults: defaults)

        checklist.complete(.customizeShortcut)
        XCTAssertEqual(checklist.pendingItems, [.createMode])
        XCTAssertTrue(checklist.isVisible)

        checklist.complete(.createMode)
        XCTAssertTrue(checklist.pendingItems.isEmpty)
        XCTAssertFalse(checklist.isVisible)

        let restored = HomeChecklistState(defaults: defaults)
        XCTAssertEqual(restored.completedItems, [.customizeShortcut, .createMode])
        XCTAssertFalse(restored.isVisible)
    }

    func testChecklistInitializesFromPersistedHotkeySignal() {
        let defaults = Self.ephemeralDefaults()
        Self.customHotkey.persist(to: defaults)
        let metrics = MetricsSnapshotStore(
            reader: EmptyMetricsReading(),
            defaults: defaults,
            logger: PersonalScribeLogger.testing(category: PersonalScribeLogCategory.ui)
        )
        let viewModel = HomeTabViewModel(
            metrics: metrics,
            defaults: defaults
        )

        XCTAssertEqual(
            viewModel.checklist.completedItems,
            [.customizeShortcut]
        )
    }

    func testChecklistEarnsSetupSignalsWhileHomeIsClosed() async throws {
        let defaults = Self.ephemeralDefaults()
        let (modeUpdates, modeContinuation) = AsyncStream<[WorkflowMode]>.makeStream()
        let checklist = HomeChecklistState(defaults: defaults)
        checklist.startObserving(customModes: modeUpdates)
        let completed = expectation(description: "All checklist signals are observed")
        let completionObservation = checklist.$completedItems
            .filter { $0 == [.customizeShortcut, .createMode] }
            .prefix(1)
            .sink { _ in completed.fulfill() }

        Self.customHotkey.persist(to: defaults)
        HotkeyPreference.default.persist(to: defaults)
        modeContinuation.yield([.dictation])
        modeContinuation.yield([])
        await fulfillment(of: [completed], timeout: 1)

        XCTAssertEqual(checklist.completedItems, [.customizeShortcut, .createMode])
        XCTAssertEqual(checklist.recordingHotkey, .default)
        XCTAssertEqual(
            HomeChecklistState(defaults: defaults).completedItems,
            [.customizeShortcut, .createMode]
        )
        withExtendedLifetime(completionObservation) {}
    }

    func testHotkeyChangesUpdateHintLiveAndKeepEarnedTick() {
        let defaults = Self.ephemeralDefaults()
        let checklist = HomeChecklistState(defaults: defaults)
        let viewModel = HomeTabViewModel(
            metrics: MetricsSnapshotStore(
                reader: EmptyMetricsReading(),
                defaults: defaults,
                logger: PersonalScribeLogger.testing(category: PersonalScribeLogCategory.ui)
            ),
            defaults: defaults,
            checklist: checklist
        )

        Self.customHotkey.persist(to: defaults)
        XCTAssertEqual(
            viewModel.emptyStateHotkeyHint,
            HotkeyShortcutFormatter.displayString(for: Self.customHotkey)
        )

        HotkeyPreference.default.persist(to: defaults)

        XCTAssertEqual(
            viewModel.emptyStateHotkeyHint,
            HotkeyShortcutFormatter.displayString(for: .default)
        )
        XCTAssertTrue(checklist.completedItems.contains(.customizeShortcut))
    }

    func testManualShortcutCompletionSurvivesLaterChangeBackToDefaultHotkey() {
        let defaults = Self.ephemeralDefaults()
        let checklist = HomeChecklistState(defaults: defaults)

        checklist.complete(.customizeShortcut)
        Self.customHotkey.persist(to: defaults)
        HotkeyPreference.default.persist(to: defaults)

        XCTAssertTrue(checklist.completedItems.contains(.customizeShortcut))
        XCTAssertTrue(
            HomeChecklistState(defaults: defaults).completedItems.contains(
                .customizeShortcut
            )
        )
    }

    func testChecklistActionsRouteShortcutAndModeRows() {
        var destinations: [String] = []
        let viewModel = HomeTabViewModel(
            metrics: MetricsSnapshotStore(
                reader: EmptyMetricsReading(),
                logger: PersonalScribeLogger.testing(category: PersonalScribeLogCategory.ui)
            ),
            openShortcuts: { destinations.append("shortcuts") },
            openModes: { destinations.append("modes") },
            openPermissions: { destinations.append("permissions") },
            openModels: { destinations.append("models") },
            openTryShortcut: { destinations.append("try") }
        )

        viewModel.performChecklistAction(for: .customizeShortcut)
        viewModel.performChecklistAction(for: .createMode)
        viewModel.performChecklistAction(for: .grantPermissions)
        viewModel.performChecklistAction(for: .downloadModel)
        viewModel.performChecklistAction(for: .tryShortcut)

        XCTAssertEqual(destinations, ["shortcuts", "modes", "permissions", "models", "try"])
    }

    func testSetupItemsDoNotAppearUntilMarkedApplicable() {
        let checklist = HomeChecklistState(defaults: Self.ephemeralDefaults())

        XCTAssertEqual(checklist.pendingItems, [.customizeShortcut, .createMode])

        checklist.markApplicable(.grantPermissions)
        checklist.markApplicable(.downloadModel)
        checklist.markApplicable(.tryShortcut)

        XCTAssertEqual(
            checklist.pendingItems,
            [.customizeShortcut, .createMode, .grantPermissions, .downloadModel, .tryShortcut]
        )
    }

    func testSatisfiedApplicableSetupItemAutoCompletes() {
        let defaults = Self.ephemeralDefaults()
        let checklist = HomeChecklistState(defaults: defaults)
        checklist.markApplicable(.downloadModel)

        checklist.refreshSetupSatisfaction(
            permissionsGranted: false,
            modelDownloaded: true,
            shortcutTried: false
        )

        XCTAssertFalse(checklist.pendingItems.contains(.downloadModel))
        XCTAssertTrue(
            HomeChecklistState(defaults: defaults).completedItems.contains(.downloadModel)
        )
    }

    func testTimeSavedFormatterUsesHourAndMinuteUnits() {
        XCTAssertEqual(HomeTab.timeSavedText(minutes: 0), "0m")
        XCTAssertEqual(HomeTab.timeSavedText(minutes: 42), "42m")
        XCTAssertEqual(HomeTab.timeSavedText(minutes: 222), "3h 42m")
        XCTAssertEqual(HomeTab.timeSavedText(minutes: 59.6), "1h 0m")
        XCTAssertEqual(HomeTab.timeSavedText(minutes: 60), "1h 0m")
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
