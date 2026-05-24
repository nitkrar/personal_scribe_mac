import XCTest
import PersonalScribeCore
import PersonalScribeSession
@testable import PersonalScribeAppKit

@MainActor
final class GeneralTabViewModelTests: XCTestCase {
    private let suiteName = "GeneralTabViewModelTests"

    private func isolatedDefaults() -> UserDefaults {
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    func test_applyVisibilityConfig_rejectsBothHidden() {
        let defaults = isolatedDefaults()
        var menuBarVisible = true
        let viewModel = GeneralTabViewModel(
            defaults: defaults,
            menuBarVisibilityProvider: { menuBarVisible },
            menuBarVisibilitySetter: { menuBarVisible = $0 }
        )

        let conflict = viewModel.applyVisibilityConfig(
            .init(
                pillVisibilityMode: .hidden,
                isMenuBarVisible: false
            )
        )

        XCTAssertEqual(conflict, .conflict)
        XCTAssertEqual(viewModel.visibilityError, .conflict)
        // View model's init resolved the fallback mode from defaults when no
        // key was set — the stored default flipped from `.autoShow` to
        // `.alwaysOn` per dogfood feedback. The conflict-rejection path
        // leaves the pre-apply mode in place, so the assertion tracks the
        // new persisted default.
        XCTAssertEqual(viewModel.pillVisibilityMode, .alwaysOn)
        XCTAssertTrue(viewModel.isMenuBarVisible)
        XCTAssertEqual(PillVisibility.resolve(from: defaults), .alwaysOn)
        XCTAssertTrue(menuBarVisible)

        let hidePillOnly = viewModel.applyVisibilityConfig(
            .init(
                pillVisibilityMode: .hidden,
                isMenuBarVisible: true
            )
        )

        XCTAssertNil(hidePillOnly)
        XCTAssertNil(viewModel.visibilityError)
        XCTAssertEqual(viewModel.pillVisibilityMode, .hidden)
        XCTAssertTrue(viewModel.isMenuBarVisible)
        XCTAssertEqual(PillVisibility.resolve(from: defaults), .hidden)
        XCTAssertTrue(menuBarVisible)

        let hideMenuOnly = viewModel.applyVisibilityConfig(
            .init(
                pillVisibilityMode: .alwaysOn,
                isMenuBarVisible: false
            )
        )

        XCTAssertNil(hideMenuOnly)
        XCTAssertNil(viewModel.visibilityError)
        XCTAssertEqual(viewModel.pillVisibilityMode, .alwaysOn)
        XCTAssertFalse(viewModel.isMenuBarVisible)
        XCTAssertEqual(PillVisibility.resolve(from: defaults), .alwaysOn)
        XCTAssertFalse(menuBarVisible)
    }

    func testInitResolvesPersistedClipboardRestoreDelay() {
        let defaults = isolatedDefaults()
        ClipboardRestoreDelay.storedSeconds(defaults: defaults).persist(1.8)

        let viewModel = GeneralTabViewModel(defaults: defaults)

        XCTAssertEqual(viewModel.clipboardRestoreDelay.seconds, 1.8, accuracy: 0.0001)
    }

    func testSetClipboardRestoreDelaySecondsPersistsAndUpdatesState() {
        let defaults = isolatedDefaults()
        let viewModel = GeneralTabViewModel(defaults: defaults)

        viewModel.setClipboardRestoreDelaySeconds(2.4)

        XCTAssertEqual(viewModel.clipboardRestoreDelay.seconds, 2.4, accuracy: 0.0001)
        XCTAssertEqual(ClipboardRestoreDelay.resolve(from: defaults).seconds, 2.4, accuracy: 0.0001)
    }

    func testInitResolvesPersistedStreamingDefaults() {
        let defaults = isolatedDefaults()
        StreamingLiveCardEnabledPreference.persist(false, to: defaults)
        StreamingLiveCursorEnabledPreference.persist(true, to: defaults)
        StreamingSecondPassEnabledPreference.persist(false, to: defaults)

        let viewModel = GeneralTabViewModel(defaults: defaults)

        XCTAssertFalse(viewModel.streamingLiveCardEnabled)
        XCTAssertTrue(viewModel.streamingLiveCursorEnabled)
        XCTAssertFalse(viewModel.streamingSecondPassEnabled)
    }

    func testSetStreamingDefaultsPersistAndPublish() {
        let defaults = isolatedDefaults()
        let viewModel = GeneralTabViewModel(defaults: defaults)

        viewModel.setStreamingLiveCardEnabled(false)
        viewModel.setStreamingLiveCursorEnabled(true)
        viewModel.setStreamingSecondPassEnabled(false)

        XCTAssertFalse(viewModel.streamingLiveCardEnabled)
        XCTAssertTrue(viewModel.streamingLiveCursorEnabled)
        XCTAssertFalse(viewModel.streamingSecondPassEnabled)
        XCTAssertFalse(StreamingLiveCardEnabledPreference.resolve(from: defaults))
        XCTAssertTrue(StreamingLiveCursorEnabledPreference.resolve(from: defaults))
        XCTAssertFalse(StreamingSecondPassEnabledPreference.resolve(from: defaults))
    }

    func testLiveCursorStreamingSuppressedWhenActiveStreamingIsWhisperCpp() {
        let defaults = isolatedDefaults()
        let service = makeModelService(
            defaults: defaults,
            activeStreamingDescriptor: BuiltInModelCatalog.whisperCppTiny
        )

        let viewModel = GeneralTabViewModel(defaults: defaults, modelService: service)

        XCTAssertTrue(viewModel.liveCursorStreamingSuppressed)
        XCTAssertNotNil(viewModel.liveCursorStreamingSuppressedReason)
    }

    func testLiveCursorStreamingNotSuppressedWhenActiveStreamingIsParakeet() {
        let defaults = isolatedDefaults()
        let service = makeModelService(
            defaults: defaults,
            activeStreamingDescriptor: BuiltInModelCatalog.parakeetEou160ms
        )

        let viewModel = GeneralTabViewModel(defaults: defaults, modelService: service)

        XCTAssertFalse(viewModel.liveCursorStreamingSuppressed)
        XCTAssertNil(viewModel.liveCursorStreamingSuppressedReason)
    }

    private func makeModelService(
        defaults: UserDefaults,
        activeStreamingDescriptor: ModelDescriptor
    ) -> ActiveModelService {
        let preference = Preference<[ModelKind: String]>(
            key: "GeneralTabViewModelTests-ActiveIDs",
            default: [:],
            defaults: defaults
        )
        preference.persist([.streamingASR: activeStreamingDescriptor.id])
        return ActiveModelService(
            activeIDsPreference: preference,
            registeredModels: [activeStreamingDescriptor],
            isDownloaded: { _ in true },
            download: { _, _ in },
            logger: PersonalScribeLogger.testing(category: PersonalScribeLogCategory.session)
        )
    }
}
