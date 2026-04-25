import Foundation
import XCTest
@testable import PersonalScribeAppKit
import PersonalScribeCore
@testable import PersonalScribeSession

/// Tests for `ModesTabViewModel` — the routing / derivation state
/// behind the unified-window Modes tab (M3.4).
@MainActor
final class ModesTabViewModelTests: XCTestCase {
    // MARK: - Fixtures

    private static let dictationMode = ModeDescriptor(
        id: "dictation",
        name: "Dictation",
        voiceModelID: BuiltInModelCatalog.parakeetTDT06Bv2.id
    )

    private static let lightweightMode = ModeDescriptor(
        id: "lightweight",
        name: "Lightweight",
        voiceModelID: BuiltInModelCatalog.parakeetTDTCTC110M.id
    )

    private static let allModes: [ModeDescriptor] = [
        dictationMode,
        lightweightMode,
    ]

    private func makeService(
        active: ModelDescriptor? = nil
    ) -> ActiveModelService {
        let suiteName = "PersonalScribeTests.ModesTabViewModel.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        addTeardownBlock {
            UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        }
        let preference = Preference<[ModelKind: String]>(
            key: ActiveModelService.preferenceKey,
            default: [:],
            defaults: defaults
        )
        if let active {
            preference.persist([.asr: active.id])
        }
        return ActiveModelService(
            activeIDsPreference: preference,
            isDownloaded: { _ in true },
            download: { _, _ in }
        )
    }

    // MARK: - Tests

    func testInitWithExplicitModesAndNoServiceLeavesActiveIDNil() {
        let viewModel = ModesTabViewModel(modes: Self.allModes)

        XCTAssertEqual(viewModel.modes, Self.allModes)
        XCTAssertNil(
            viewModel.activeModeID,
            "Without a service, activeModeID must be nil after init."
        )
    }

    func testInitReadsActiveModeFromService() {
        let service = makeService(active: BuiltInModelCatalog.parakeetTDTCTC110M)
        let viewModel = ModesTabViewModel(
            modes: Self.allModes,
            modelService: service
        )

        XCTAssertEqual(viewModel.activeModeID, Self.lightweightMode.id)
    }

    func testIsActiveReturnsTrueForActiveMode() {
        let service = makeService(active: BuiltInModelCatalog.parakeetTDT06Bv2)
        let viewModel = ModesTabViewModel(
            modes: Self.allModes,
            modelService: service
        )

        XCTAssertTrue(viewModel.isActive(Self.dictationMode))
        XCTAssertFalse(viewModel.isActive(Self.lightweightMode))
    }

    func testIsActiveReturnsFalseWhenNoActiveMode() {
        let viewModel = ModesTabViewModel(modes: Self.allModes)

        for mode in Self.allModes {
            XCTAssertFalse(
                viewModel.isActive(mode),
                "With no active mode, isActive must be false for every mode (got true for \(mode.id))."
            )
        }
    }

    func testDefaultModesComeFromModeRegistry() {
        let viewModel = ModesTabViewModel()

        XCTAssertEqual(
            viewModel.modes,
            ModeRegistry.all,
            "The default mode list must mirror ModeRegistry.all so the tab renders every registered mode."
        )
    }

    // MARK: - setActive write path

    func testSetActiveInvokesInjectedHandlerWithSelectedMode() async {
        actor Recorder {
            var received: [String] = []
            func record(_ id: String) { received.append(id) }
        }
        let recorder = Recorder()

        let viewModel = ModesTabViewModel(
            modes: Self.allModes,
            setActiveHandler: { mode in
                await recorder.record(mode.id)
            }
        )

        await viewModel.setActive(Self.lightweightMode)

        let received = await recorder.received
        XCTAssertEqual(received, [Self.lightweightMode.id])
    }

    // MARK: - Combine subscription on $activeModelIDs

    /// Flipping the underlying service's `.asr` slot must propagate
    /// into `activeModeID` via the Combine sink. Pins the live-update
    /// behavior the AI Models tab relies on.
    func testActiveModeIDFollowsServiceFlips() async {
        let service = makeService()
        let viewModel = ModesTabViewModel(
            modes: Self.allModes,
            modelService: service
        )
        XCTAssertNil(viewModel.activeModeID)

        service.setActive(BuiltInModelCatalog.parakeetTDT06Bv2)
        for _ in 0..<500 {
            if viewModel.activeModeID == Self.dictationMode.id { break }
            await Task.yield()
        }
        XCTAssertEqual(viewModel.activeModeID, Self.dictationMode.id)

        service.setActive(BuiltInModelCatalog.parakeetTDTCTC110M)
        for _ in 0..<500 {
            if viewModel.activeModeID == Self.lightweightMode.id { break }
            await Task.yield()
        }
        XCTAssertEqual(viewModel.activeModeID, Self.lightweightMode.id)
    }
}
