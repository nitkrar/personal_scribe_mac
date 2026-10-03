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

    func testSetWaveformPalettePublishesAndPersistsSelection() {
        let defaults = isolatedDefaults()
        let viewModel = GeneralTabViewModel(defaults: defaults)
        XCTAssertEqual(viewModel.waveformPalette, .siri)

        viewModel.setWaveformPalette(.sunset)

        XCTAssertEqual(viewModel.waveformPalette, .sunset)
        XCTAssertEqual(WaveformPalette.resolve(from: defaults), .sunset)
        XCTAssertEqual(GeneralTabViewModel(defaults: defaults).waveformPalette, .sunset)
    }

    func testApplyVisibilityConfigPersistsPillModeAndMenuBar() {
        let defaults = isolatedDefaults()
        var menuBarVisible = true
        let viewModel = GeneralTabViewModel(
            defaults: defaults,
            menuBarVisibilityProvider: { menuBarVisible },
            menuBarVisibilitySetter: { menuBarVisible = $0 }
        )

        viewModel.applyVisibilityConfig(.init(pillVisibilityMode: .autoShow, isMenuBarVisible: false))

        XCTAssertEqual(viewModel.pillVisibilityMode, .autoShow)
        XCTAssertEqual(PillVisibility.resolve(from: defaults), .autoShow)
        XCTAssertFalse(viewModel.isMenuBarVisible)
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

    func testSetCancelCardDurationPersistsAndUpdatesState() {
        let defaults = isolatedDefaults()
        let viewModel = GeneralTabViewModel(defaults: defaults)
        XCTAssertEqual(viewModel.cancelCardDuration.seconds, 3)

        viewModel.setCancelCardDurationSeconds(5)

        XCTAssertEqual(viewModel.cancelCardDuration.seconds, 5)
        XCTAssertEqual(CancelCardDuration.resolve(from: defaults).seconds, 5)
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
