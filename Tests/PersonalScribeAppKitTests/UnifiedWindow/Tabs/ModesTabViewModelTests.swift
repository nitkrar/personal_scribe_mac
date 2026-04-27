import Foundation
import XCTest
@testable import PersonalScribeAppKit
import PersonalScribeCore
@testable import PersonalScribeSession

/// Tests for `ModesTabViewModel` — the routing / derivation state
/// behind the unified-window Modes tab (M3.4). Post-#078.36 the view
/// model reads from `WorkflowModeRegistry` (per L21) instead of
/// matching modes against `ActiveModelService.activeModelIDs[.asr]`.
@MainActor
final class ModesTabViewModelTests: XCTestCase {
    // MARK: - Fixtures

    private static let codingMode = WorkflowMode(
        id: "coding",
        name: "Coding",
        pipelineShape: .batch,
        processors: [.transcriber(kind: .asr)],
        captureControllers: [.manualHotkey],
        outputSinks: [.frontmostPaste]
    )

    private static let allModes: [WorkflowMode] = [
        WorkflowMode.dictation,
        codingMode,
    ]

    private func makeRegistry() -> WorkflowModeRegistry {
        // swiftlint:disable:next force_try
        try! WorkflowModeRegistry(
            store: InMemoryWorkflowModeStore(),
            availableKindsProvider: { Set(ModelKind.allCases) }
        )
    }

    // MARK: - Tests

    func testInitWithoutRegistryDefaultsToDictation() {
        let viewModel = ModesTabViewModel(modes: Self.allModes)

        XCTAssertEqual(viewModel.modes, Self.allModes)
        XCTAssertEqual(viewModel.activeModeID, WorkflowMode.dictation.id)
    }

    func testInitReadsActiveModeFromRegistry() throws {
        let registry = makeRegistry()
        try registry.saveCustom(Self.codingMode)
        try registry.setActive(id: Self.codingMode.id)

        let viewModel = ModesTabViewModel(
            modes: Self.allModes,
            registry: registry
        )

        XCTAssertEqual(viewModel.activeModeID, Self.codingMode.id)
    }

    func testIsActiveReturnsTrueForActiveMode() throws {
        let registry = makeRegistry()
        try registry.saveCustom(Self.codingMode)
        try registry.setActive(id: Self.codingMode.id)
        let viewModel = ModesTabViewModel(
            modes: Self.allModes,
            registry: registry
        )

        XCTAssertTrue(viewModel.isActive(Self.codingMode))
        XCTAssertFalse(viewModel.isActive(WorkflowMode.dictation))
    }

    func testDefaultModesComeFromBuiltInRegistry() {
        let viewModel = ModesTabViewModel()

        XCTAssertEqual(
            viewModel.modes,
            WorkflowModeRegistry.builtInModes,
            "The default mode list must mirror WorkflowModeRegistry.builtInModes so the tab renders every registered built-in."
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

        await viewModel.setActive(Self.codingMode)

        let received = await recorder.received
        XCTAssertEqual(received, [Self.codingMode.id])
    }

    // MARK: - Stream subscription

    /// Flipping the registry's active mode must propagate into
    /// `activeModeID` via the AsyncStream subscription.
    func testActiveModeIDFollowsRegistryFlips() async throws {
        let registry = makeRegistry()
        try registry.saveCustom(Self.codingMode)

        let viewModel = ModesTabViewModel(
            modes: Self.allModes,
            registry: registry
        )

        try registry.setActive(id: Self.codingMode.id)
        for _ in 0..<500 {
            if viewModel.activeModeID == Self.codingMode.id { break }
            try? await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertEqual(viewModel.activeModeID, Self.codingMode.id)

        try registry.setActive(id: WorkflowMode.dictation.id)
        for _ in 0..<500 {
            if viewModel.activeModeID == WorkflowMode.dictation.id { break }
            try? await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertEqual(viewModel.activeModeID, WorkflowMode.dictation.id)
    }
}
