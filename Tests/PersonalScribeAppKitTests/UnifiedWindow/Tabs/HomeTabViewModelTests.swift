import AppKit
import Combine
import Foundation
import XCTest
@testable import PersonalScribeAppKit
import PersonalScribeCore

@MainActor
final class HomeTabViewModelTests: XCTestCase {
    func testChecklistRestoresEachPersistedAchievement() {
        let defaults = Self.ephemeralDefaults()
        defaults.set(true, forKey: "HomeChecklistStartRecordingComplete")
        defaults.set(true, forKey: "HomeChecklistCreateModeComplete")

        let checklist = HomeChecklistState(defaults: defaults)

        XCTAssertEqual(checklist.completedItems, [.startRecording, .createMode])
        XCTAssertEqual(checklist.completedCount, 2)
    }

    func testChecklistDismissesOnlyWhenCompleteAndRestoresDismissal() {
        let defaults = Self.ephemeralDefaults()
        var checklist = HomeChecklistState(defaults: defaults)

        checklist.dismiss()
        XCTAssertFalse(checklist.isDismissed)

        defaults.set(true, forKey: "HomeChecklistStartRecordingComplete")
        defaults.set(true, forKey: "HomeChecklistCustomizeShortcutComplete")
        defaults.set(true, forKey: "HomeChecklistCreateModeComplete")
        checklist = HomeChecklistState(defaults: defaults)
        checklist.dismiss()
        XCTAssertTrue(checklist.isDismissed)

        checklist = HomeChecklistState(defaults: defaults)
        XCTAssertTrue(checklist.isDismissed)
        XCTAssertFalse(checklist.isVisible)
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

    func testChecklistEarnsSignalsWhileHomeIsClosed() async throws {
        let defaults = Self.ephemeralDefaults()
        let referenceDate = Date(timeIntervalSince1970: 2_000_000)
        let window = MetricsWindow(start: .distantPast, end: referenceDate)
        let entry = TranscriptEntry(
            id: UUID(),
            timestamp: referenceDate.addingTimeInterval(-60),
            text: "earned while closed",
            audioDuration: 10,
            processingDuration: 0.1
        )
        let snapshot = MetricsSnapshot(
            rollups: MetricsRollups(
                recordings: 1,
                words: 3,
                minutesSaved: 0,
                averageWPM: 18,
                sampleCount: 1,
                windowStart: window.start,
                windowEnd: window.end
            ),
            recentTranscriptions: [entry],
            lastUpdatedAt: referenceDate,
            lastRefreshReason: .transcriptCommit
        )
        let metrics = MetricsSnapshotStore(
            reader: FixedHomeMetricsReader(snapshot: snapshot),
            referenceDateProvider: { referenceDate },
            defaults: defaults,
            logger: PersonalScribeLogger.testing(category: PersonalScribeLogCategory.ui)
        )
        let (modeUpdates, modeContinuation) = AsyncStream<[WorkflowMode]>.makeStream()
        let checklist = HomeChecklistState(defaults: defaults)
        checklist.startObserving(metrics: metrics, customModes: modeUpdates)
        let completed = expectation(description: "All checklist signals are observed")
        let completionObservation = checklist.$completedItems
            .filter { $0 == Set(HomeChecklistItem.allCases) }
            .prefix(1)
            .sink { _ in completed.fulfill() }

        Self.customHotkey.persist(to: defaults)
        HotkeyPreference.default.persist(to: defaults)
        modeContinuation.yield([.dictation])
        modeContinuation.yield([])
        await metrics.refresh(reason: .transcriptCommit)
        await fulfillment(of: [completed], timeout: 1)

        XCTAssertEqual(checklist.completedItems, Set(HomeChecklistItem.allCases))
        XCTAssertEqual(checklist.recordingHotkey, .default)
        XCTAssertEqual(
            HomeChecklistState(defaults: defaults).completedItems,
            Set(HomeChecklistItem.allCases)
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

private struct FixedHomeMetricsReader: MetricsReading {
    let snapshot: MetricsSnapshot

    func loadSnapshot(window: MetricsWindow, recentLimit: Int) async throws -> MetricsSnapshot {
        snapshot
    }

    func recentTranscriptions(limit: Int) async throws -> [TranscriptEntry] {
        Array(snapshot.recentTranscriptions.prefix(limit))
    }
}
