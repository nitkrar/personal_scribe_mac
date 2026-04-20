import XCTest
@testable import PersonalScribeAppKit
import PersonalScribeCore

/// Tests for `ModesTabViewModel` — the routing / derivation state
/// behind the unified-window Modes tab (M3.4).
@MainActor
final class ModesTabViewModelTests: XCTestCase {
    // MARK: - Fixtures

    private static let dictationMode = ModeDescriptor(
        id: "dictation",
        name: "Dictation",
        voiceModelID: "parakeet-tdt-0.6b-v2"
    )

    private static let commandMode = ModeDescriptor(
        id: "command",
        name: "Command",
        voiceModelID: "parakeet-tdt-0.6b-v2",
        aiModelID: "instruction",
        systemPrompt: "Execute the user's command."
    )

    private static let notesMode = ModeDescriptor(
        id: "notes",
        name: "Notes",
        voiceModelID: "parakeet-tdt-0.6b-v2",
        aiModelID: "summariser"
    )

    private static let allModes: [ModeDescriptor] = [
        dictationMode,
        commandMode,
        notesMode,
    ]

    // MARK: - Tests

    func testInitWithExplicitModes() {
        let viewModel = ModesTabViewModel(modes: Self.allModes)

        XCTAssertEqual(viewModel.modes, Self.allModes)
        XCTAssertNil(
            viewModel.activeModeID,
            "Default provider returns nil, so activeModeID must be nil after init."
        )
    }

    func testInitReadsActiveModeFromProvider() {
        let viewModel = ModesTabViewModel(
            modes: Self.allModes,
            activeModeProvider: { Self.commandMode }
        )

        XCTAssertEqual(viewModel.activeModeID, Self.commandMode.id)
    }

    func testIsActiveReturnsTrueForActiveMode() {
        let viewModel = ModesTabViewModel(
            modes: Self.allModes,
            activeModeProvider: { Self.notesMode }
        )

        XCTAssertTrue(viewModel.isActive(Self.notesMode))
    }

    func testIsActiveReturnsFalseForInactiveMode() {
        let viewModel = ModesTabViewModel(
            modes: Self.allModes,
            activeModeProvider: { Self.notesMode }
        )

        XCTAssertFalse(viewModel.isActive(Self.dictationMode))
        XCTAssertFalse(viewModel.isActive(Self.commandMode))
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

    func testRefreshActiveModeUpdatesActiveModeID() {
        final class ActiveBox { var current: ModeDescriptor? }
        let box = ActiveBox()

        let viewModel = ModesTabViewModel(
            modes: Self.allModes,
            activeModeProvider: { box.current }
        )

        XCTAssertNil(viewModel.activeModeID)

        box.current = Self.dictationMode
        viewModel.refreshActiveMode()
        XCTAssertEqual(viewModel.activeModeID, Self.dictationMode.id)

        box.current = Self.commandMode
        viewModel.refreshActiveMode()
        XCTAssertEqual(viewModel.activeModeID, Self.commandMode.id)

        box.current = nil
        viewModel.refreshActiveMode()
        XCTAssertNil(viewModel.activeModeID)
    }

    func testDefaultModesComeFromModeRegistry() {
        let viewModel = ModesTabViewModel()

        XCTAssertEqual(
            viewModel.modes,
            ModeRegistry.all,
            "The default mode list must mirror ModeRegistry.all so the tab renders every registered mode."
        )
    }
}
