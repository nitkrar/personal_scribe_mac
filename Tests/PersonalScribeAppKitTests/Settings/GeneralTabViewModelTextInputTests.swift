import XCTest
@testable import PersonalScribeAppKit

/// Tests for the "Transcribe output" section's view-model wiring on
/// `GeneralTabViewModel`. Replaces pre-#072 TEXT INPUT tests — the
/// `pasteEnabled` master + `pasteMode` picker were collapsed into a
/// single `autoPasteEnabled` toggle (default `true`), and
/// `clipboardRestoreEnabled` was added (default `false`).
@MainActor
final class GeneralTabViewModelTextInputTests: XCTestCase {
    // MARK: - Auto-paste toggle

    func testInitReadsAutoPasteEnabledFromDefaults() {
        let defaults = Self.isolatedDefaults()
        AutoPasteEnabledPreference.persist(false, to: defaults)

        let viewModel = GeneralTabViewModel(defaults: defaults)

        XCTAssertFalse(viewModel.autoPasteEnabled)
    }

    func testInitFallsBackToAutoPasteTrueWhenDefaultsEmpty() {
        let defaults = Self.isolatedDefaults()

        let viewModel = GeneralTabViewModel(defaults: defaults)

        XCTAssertTrue(viewModel.autoPasteEnabled)
    }

    func testSetAutoPasteEnabledPersistsAndPublishes() {
        let defaults = Self.isolatedDefaults()
        let viewModel = GeneralTabViewModel(defaults: defaults)

        viewModel.setAutoPasteEnabled(false)

        XCTAssertFalse(viewModel.autoPasteEnabled)
        XCTAssertEqual(
            defaults.object(forKey: "AutoPasteEnabled") as? Bool,
            false
        )
    }

    // MARK: - Restore clipboard toggle

    func testInitFallsBackToRestoreDisabledWhenDefaultsEmpty() {
        let defaults = Self.isolatedDefaults()

        let viewModel = GeneralTabViewModel(defaults: defaults)

        XCTAssertFalse(viewModel.clipboardRestoreEnabled)
    }

    func testInitReadsClipboardRestoreEnabledFromDefaults() {
        let defaults = Self.isolatedDefaults()
        ClipboardRestoreEnabledPreference.persist(true, to: defaults)

        let viewModel = GeneralTabViewModel(defaults: defaults)

        XCTAssertTrue(viewModel.clipboardRestoreEnabled)
    }

    func testSetClipboardRestoreEnabledPersistsAndPublishes() {
        let defaults = Self.isolatedDefaults()
        let viewModel = GeneralTabViewModel(defaults: defaults)

        viewModel.setClipboardRestoreEnabled(true)

        XCTAssertTrue(viewModel.clipboardRestoreEnabled)
        XCTAssertEqual(
            defaults.object(forKey: "ClipboardRestoreEnabled") as? Bool,
            true
        )
    }

    // MARK: - Summary caption adapts to toggle state

    func testSummaryDescribesAutoPasteOnRestoreOn() {
        let defaults = Self.isolatedDefaults()
        AutoPasteEnabledPreference.persist(true, to: defaults)
        ClipboardRestoreEnabledPreference.persist(true, to: defaults)

        let viewModel = GeneralTabViewModel(defaults: defaults)

        XCTAssertTrue(viewModel.transcribeOutputSummary.contains("paste into the focused text field"))
        XCTAssertTrue(viewModel.transcribeOutputSummary.contains("your previous clipboard is restored"))
    }

    func testSummaryDescribesAutoPasteOnRestoreOff() {
        let defaults = Self.isolatedDefaults()
        AutoPasteEnabledPreference.persist(true, to: defaults)
        ClipboardRestoreEnabledPreference.persist(false, to: defaults)

        let viewModel = GeneralTabViewModel(defaults: defaults)

        XCTAssertTrue(viewModel.transcribeOutputSummary.contains("paste into the focused text field"))
        XCTAssertTrue(viewModel.transcribeOutputSummary.contains("until you copy something else"))
    }

    func testSummaryDescribesAutoPasteOffRestoreOn() {
        let defaults = Self.isolatedDefaults()
        AutoPasteEnabledPreference.persist(false, to: defaults)
        ClipboardRestoreEnabledPreference.persist(true, to: defaults)

        let viewModel = GeneralTabViewModel(defaults: defaults)

        XCTAssertTrue(viewModel.transcribeOutputSummary.contains("⌘V to paste"))
        XCTAssertTrue(viewModel.transcribeOutputSummary.contains("your previous clipboard is restored"))
    }

    func testSummaryDescribesBothOff() {
        let defaults = Self.isolatedDefaults()
        AutoPasteEnabledPreference.persist(false, to: defaults)
        ClipboardRestoreEnabledPreference.persist(false, to: defaults)

        let viewModel = GeneralTabViewModel(defaults: defaults)

        XCTAssertTrue(viewModel.transcribeOutputSummary.contains("⌘V to paste"))
        XCTAssertTrue(viewModel.transcribeOutputSummary.contains("is not restored"))
    }

    private static func isolatedDefaults() -> UserDefaults {
        let suiteName = "GeneralTabViewModelTextInputTests-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            fatalError("Could not create isolated UserDefaults for test")
        }
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
