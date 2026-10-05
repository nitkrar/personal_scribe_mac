import Foundation
import XCTest
@testable import PersonalScribeAppKit
import PersonalScribeCore

@MainActor
final class SetupFlowStateTests: XCTestCase {
    func testIncompleteOnboardingOpensAtPermissionsAndStaysOpenAfterFlagFlips() {
        let defaults = Self.ephemeralDefaults()
        let flow = SetupFlowState(defaults: defaults)

        XCTAssertTrue(flow.isOpen)
        XCTAssertEqual(flow.step, .permissions)
        XCTAssertEqual(flow.completedStepCount, 0)

        OnboardingState.completed.persist(to: defaults)

        XCTAssertTrue(flow.isOpen)
        XCTAssertEqual(flow.step, .permissions)
    }

    func testCompletedOnboardingDoesNotOpenForExistingUser() {
        let defaults = Self.ephemeralDefaults()
        OnboardingState.completed.persist(to: defaults)

        XCTAssertFalse(SetupFlowState(defaults: defaults).isOpen)
    }

    func testSkipWithMicrophoneMissingLeavesFutureSetupOpen() {
        let defaults = Self.ephemeralDefaults()
        let flow = SetupFlowState(defaults: defaults)

        flow.skip(satisfaction: SetupSatisfaction(
            permissionsGranted: false,
            modelDownloaded: true,
            shortcutTried: true
        ))

        XCTAssertEqual(OnboardingState.resolve(from: defaults), .incomplete)
        XCTAssertTrue(SetupFlowState(defaults: defaults).isOpen)
    }

    func testOpenFlowCanSkipOptionalStepsAfterMicGrantWithoutReopening() {
        let defaults = Self.ephemeralDefaults()
        let checklist = HomeChecklistState(defaults: defaults)
        let flow = SetupFlowState(defaults: defaults, checklist: checklist)
        OnboardingState.completed.persist(to: defaults)

        flow.skip(satisfaction: SetupSatisfaction(
            permissionsGranted: false,
            modelDownloaded: true,
            shortcutTried: false
        ))

        XCTAssertFalse(SetupFlowState(defaults: defaults).isOpen)
        XCTAssertTrue(checklist.pendingItems.contains(.grantPermissions))
        XCTAssertTrue(checklist.pendingItems.contains(.tryShortcut))
    }

    func testBackAndContinueNavigateFiveStepFlow() {
        let flow = SetupFlowState(defaults: Self.ephemeralDefaults())

        XCTAssertFalse(flow.canGoBack)
        flow.advance(satisfaction: .allSatisfied)
        XCTAssertEqual(flow.step, .microphone)
        XCTAssertTrue(flow.canGoBack)
        XCTAssertEqual(flow.completedStepCount, 1)

        flow.advance(satisfaction: .allSatisfied)
        flow.advance(satisfaction: .allSatisfied)
        XCTAssertEqual(flow.step, .tryShortcut)
        flow.goBack()
        XCTAssertEqual(flow.step, .voiceModel)
    }

    func testFinishingClosesSetupShowsBannerAndAppliesOnlyUnsatisfiedItems() {
        let defaults = Self.ephemeralDefaults()
        let checklist = HomeChecklistState(defaults: defaults)
        let flow = SetupFlowState(defaults: defaults, checklist: checklist)
        let satisfaction = SetupSatisfaction(
            permissionsGranted: false,
            modelDownloaded: true,
            shortcutTried: false
        )
        flow.advance(satisfaction: satisfaction)
        flow.advance(satisfaction: satisfaction)
        flow.advance(satisfaction: satisfaction)
        flow.advance(satisfaction: satisfaction)

        XCTAssertFalse(flow.isOpen)
        XCTAssertEqual(flow.step, .done)
        XCTAssertTrue(flow.isCompletionBannerVisible)
        XCTAssertEqual(
            checklist.pendingItems,
            [.customizeShortcut, .createMode, .grantPermissions, .tryShortcut]
        )
    }

    func testSkipClosesSetupAndPersistsApplicablePendingItems() {
        let defaults = Self.ephemeralDefaults()
        let checklist = HomeChecklistState(defaults: defaults)
        let flow = SetupFlowState(defaults: defaults, checklist: checklist)

        flow.skip(
            satisfaction: SetupSatisfaction(
                permissionsGranted: true,
                modelDownloaded: false,
                shortcutTried: false
            )
        )

        XCTAssertFalse(flow.isOpen)
        XCTAssertEqual(
            checklist.pendingItems,
            [.customizeShortcut, .createMode, .downloadModel, .tryShortcut]
        )
        XCTAssertEqual(
            HomeChecklistState(defaults: defaults).pendingItems,
            [.customizeShortcut, .createMode, .downloadModel, .tryShortcut]
        )
    }

    func testPracticeSuccessRecordsWordsElapsedTimeAndCompletesPendingItem() {
        let defaults = Self.ephemeralDefaults()
        let checklist = HomeChecklistState(defaults: defaults)
        checklist.markApplicable(.tryShortcut)
        var now = Date(timeIntervalSince1970: 100)
        let flow = SetupFlowState(
            defaults: defaults,
            checklist: checklist,
            now: { now }
        )
        flow.beginPractice()
        now = Date(timeIntervalSince1970: 110)
        flow.recordPracticeStopped()
        now = Date(timeIntervalSince1970: 111.25)

        flow.updatePracticeText("Typed prefix Hello Ninimma")
        flow.recordPracticePaste("Hello Ninimma")

        XCTAssertEqual(flow.practiceResult?.wordCount, 2)
        XCTAssertEqual(flow.practiceResult?.elapsedSeconds, 1.25)
        XCTAssertTrue(flow.satisfaction.shortcutTried)
        XCTAssertFalse(checklist.pendingItems.contains(.tryShortcut))
    }

    func testPasteWithoutRecordingStopDoesNotCompletePractice() {
        let defaults = Self.ephemeralDefaults()
        let checklist = HomeChecklistState(defaults: defaults)
        checklist.markApplicable(.tryShortcut)
        let flow = SetupFlowState(defaults: defaults, checklist: checklist)

        flow.beginPractice()
        flow.updatePracticeText("Manually pasted text")
        flow.recordPracticePaste("Manually pasted text")

        XCTAssertNil(flow.practiceResult)
        XCTAssertFalse(flow.satisfaction.shortcutTried)
        XCTAssertTrue(checklist.pendingItems.contains(.tryShortcut))
    }

    func testRecordingStopCanCompleteOnlyOnePaste() {
        let defaults = Self.ephemeralDefaults()
        let flow = SetupFlowState(defaults: defaults)
        flow.beginPractice()
        flow.recordPracticeStopped()

        flow.recordPracticePaste("")
        flow.recordPracticePaste("Later manual paste")

        XCTAssertNil(flow.practiceResult)
    }

    func testTypingInPracticeEditorDoesNotCountAsShortcutTry() {
        let defaults = Self.ephemeralDefaults()
        let checklist = HomeChecklistState(defaults: defaults)
        checklist.markApplicable(.tryShortcut)
        let flow = SetupFlowState(defaults: defaults, checklist: checklist)

        flow.beginPractice()
        flow.updatePracticeText("Typed instead of dictated")

        XCTAssertEqual(flow.practiceText, "Typed instead of dictated")
        XCTAssertNil(flow.practiceResult)
        XCTAssertFalse(flow.satisfaction.shortcutTried)
        XCTAssertTrue(checklist.pendingItems.contains(.tryShortcut))
    }

    private static func ephemeralDefaults(function: String = #function) -> UserDefaults {
        let suite = "SetupFlowStateTests.\(function).\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }
}
