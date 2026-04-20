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

        await viewModel.setActive(Self.commandMode)

        let received = await recorder.received
        XCTAssertEqual(received, [Self.commandMode.id])
    }

    // MARK: - activeModeStream subscription

    func testViewModelPublishesActiveModeChangesFromStream() async {
        let (stream, continuation) = AsyncStream<ModeDescriptor?>.makeStream()

        let viewModel = ModesTabViewModel(
            modes: Self.allModes,
            activeModeProvider: { nil },
            activeModeStream: { stream }
        )

        continuation.yield(Self.dictationMode)
        for _ in 0..<500 {
            if viewModel.activeModeID == Self.dictationMode.id { break }
            await Task.yield()
        }
        XCTAssertEqual(viewModel.activeModeID, Self.dictationMode.id)

        continuation.yield(Self.commandMode)
        for _ in 0..<500 {
            if viewModel.activeModeID == Self.commandMode.id { break }
            await Task.yield()
        }
        XCTAssertEqual(viewModel.activeModeID, Self.commandMode.id)

        continuation.yield(nil)
        for _ in 0..<500 {
            if viewModel.activeModeID == nil { break }
            await Task.yield()
        }
        XCTAssertNil(viewModel.activeModeID)

        continuation.finish()
    }
}
