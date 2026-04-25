import AppKit
import Combine
import XCTest
import PersonalScribeCore
@testable import PersonalScribeAppKit

/// Host-level tests for `PasteboardSnapshotHost` — the composition-layer
/// wrapper that subscribes to `AppStore.objectWillChange` and drives the
/// shared `PasteboardSnapshotService` on session-state edges. Closes the
/// pre-#072 coverage gap: the wrapper had no direct tests, only the
/// underlying service did.
///
/// Tests observe behavior through a fake pasteboard (reads + writes on the
/// injected `PasteboardSnapshotService`) rather than spying on the service
/// directly — the service is `final`, so subclassing isn't an option, and
/// closure-seam observation is actually more robust to refactors.
@MainActor
final class PasteboardSnapshotHostTests: XCTestCase {
    private final class FakePasteboard {
        var items: [NSPasteboardItem] = []
        var changeCount: Int = 0

        func writeString(_ string: String) {
            let item = NSPasteboardItem()
            item.setString(string, forType: .string)
            items = [item]
            changeCount += 1
        }

        var firstString: String? {
            items.first?.string(forType: .string)
        }
    }

    private func makeSnapshotService(backing: FakePasteboard) -> PasteboardSnapshotService {
        PasteboardSnapshotService(
            itemsReader: { backing.items },
            itemsWriter: { items in
                backing.items = items
                backing.changeCount += 1
            },
            stringWriter: { string in
                backing.writeString(string)
                return true
            },
            changeCountReader: { backing.changeCount }
        )
    }

    /// Build a full AppStore + host wiring. Reuses the fakes pattern from
    /// the AppStore test suite but inlined so AppKit tests don't depend on
    /// the Core-tests fake target.
    private func makeAppStoreAndHost(
        backing: FakePasteboard
    ) -> (AppStore, FakeSessionProvider, PillOverlayViewModel, PasteboardSnapshotService, PasteboardSnapshotHost) {
        let sessionProvider = FakeSessionProvider()
        let permissionService = FakePermissionService()
        let appStore = AppStore(
            session: sessionProvider,
            permissions: permissionService,
            activeModeSource: FakeActiveModeProvider(),
            visibilityModeSource: FakeVisibilityModeProvider()
        )
        let viewModel = PillOverlayViewModel()
        let service = makeSnapshotService(backing: backing)
        let host = PasteboardSnapshotHost(
            appStore: appStore,
            viewModel: viewModel,
            service: service
        )
        appStore.start()
        return (appStore, sessionProvider, viewModel, service, host)
    }

    /// Drives an async state emission and waits for the host's sink to
    /// catch up. The AppStore observation Task hops through the main
    /// actor; a short sleep yields enough for the Combine sink to run.
    private func emitAndSettle(
        _ state: SessionState,
        on provider: FakeSessionProvider
    ) async {
        provider.emitState(state)
        // Three yields: one for AppStore's consuming Task, one for the
        // snapshot publish, one for the Combine sink on the host.
        for _ in 0..<5 {
            await Task.yield()
        }
    }

    // MARK: - idle → recording captures

    func testHostCapturesIntoCancelUndoSlotOnIdleToRecordingTransition() async {
        let backing = FakePasteboard()
        backing.writeString("user pre-recording clipboard")

        let (_, provider, _, service, host) = makeAppStoreAndHost(backing: backing)
        _ = host // retain for the lifetime of the test

        await emitAndSettle(.recording, on: provider)

        // Overwrite clipboard post-capture and restore via the slot API:
        // if the host captured, the slot now holds the pre-recording
        // contents and restoring will bring them back.
        backing.writeString("transcript replaced it")
        let didRestore = service.restoreSnapshot(from: .cancelUndo)

        XCTAssertTrue(didRestore, "Host should have captured on idle→recording")
        XCTAssertEqual(backing.firstString, "user pre-recording clipboard")
    }

    // MARK: - transcribing → idle clears

    func testHostClearsCancelUndoSlotOnTranscribingToIdleTransition() async {
        let backing = FakePasteboard()
        backing.writeString("user pre-recording clipboard")

        let (_, provider, _, service, host) = makeAppStoreAndHost(backing: backing)
        _ = host

        // Walk the canonical happy path: idle → recording → transcribing → idle.
        await emitAndSettle(.recording, on: provider)
        await emitAndSettle(.transcribing, on: provider)
        await emitAndSettle(.idle, on: provider)

        // Slot should be empty now — restore must return false.
        backing.writeString("new content")
        let didRestore = service.restoreSnapshot(from: .cancelUndo)

        XCTAssertFalse(didRestore, "Host should have cleared the slot on transcribing→idle")
        XCTAssertEqual(backing.firstString, "new content", "Clear must not write to pasteboard")
    }

    // MARK: - Undo closure restores

    func testHostRestoresCancelUndoSlotWhenUndoClosureFires() async {
        let backing = FakePasteboard()
        backing.writeString("user pre-recording clipboard")

        let (_, provider, viewModel, _, host) = makeAppStoreAndHost(backing: backing)
        _ = host

        await emitAndSettle(.recording, on: provider)
        backing.writeString("transcript replaced it")

        // Simulate the user clicking Undo on the Cancel Card — the host
        // wired `viewModel.onUndoCancelledRecording` in its init.
        XCTAssertNotNil(viewModel.onUndoCancelledRecording)
        viewModel.onUndoCancelledRecording?()

        XCTAssertEqual(backing.firstString, "user pre-recording clipboard")
    }

    // MARK: - Non-capture transitions stay silent

    func testHostDoesNotCaptureOnRecordingToTranscribingEdge() async {
        let backing = FakePasteboard()
        backing.writeString("pre-recording")

        let (_, provider, _, service, host) = makeAppStoreAndHost(backing: backing)
        _ = host

        // Go idle → recording (should capture).
        await emitAndSettle(.recording, on: provider)
        // Consume the slot to prove a snapshot existed.
        let captured = service.restoreSnapshot(from: .cancelUndo)
        XCTAssertTrue(captured, "Sanity: idle→recording should have captured")

        backing.writeString("midway value")

        // Now recording → transcribing — must NOT capture anew.
        await emitAndSettle(.transcribing, on: provider)

        backing.writeString("something else")
        let shouldBeEmpty = service.restoreSnapshot(from: .cancelUndo)
        XCTAssertFalse(
            shouldBeEmpty,
            "recording→transcribing is not a capture edge; slot must stay empty"
        )
    }
}

// MARK: - Inlined AppStore provider fakes (AppKit tests can't reach Core-tests fakes)

private final class FakeSessionProvider: @unchecked Sendable, AppStoreSessionProviding {
    private var currentSnapshot: SessionSnapshot
    private var continuations: [UUID: AsyncStream<SessionSnapshot>.Continuation] = [:]

    init(initialState: SessionState = .idle) {
        self.currentSnapshot = SessionSnapshot(sessionState: initialState)
    }

    func snapshotStream() -> AsyncStream<SessionSnapshot> {
        let id = UUID()
        return AsyncStream { continuation in
            continuation.yield(self.currentSnapshot)
            self.continuations[id] = continuation
            continuation.onTermination = { [weak self] _ in
                self?.continuations[id] = nil
            }
        }
    }

    func emitState(_ state: SessionState) {
        currentSnapshot.sessionState = state
        for continuation in continuations.values {
            continuation.yield(currentSnapshot)
        }
    }
}

@MainActor
private final class FakePermissionService: PermissionService {
    @Published private(set) var statuses: [Permission: PermissionStatus] = [
        .microphone: .granted,
        .inputMonitoring: .granted,
        .accessibility: .granted,
    ]

    func status(for permission: Permission) -> PermissionStatus {
        statuses[permission] ?? .pending
    }

    func request(_ permission: Permission) async -> RequestOutcome {
        RequestOutcome(
            prompted: false,
            openedSettings: false,
            requiresRelaunch: false,
            finalStatus: status(for: permission)
        )
    }

    func statusSnapshot() -> [Permission: PermissionStatus] {
        statuses
    }

    func refresh() {}

    func systemSettingsDeepLink(for permission: Permission) -> URL {
        URL(string: "https://example.invalid/\(permission.rawValue)")!
    }
}

private final class FakeActiveModeProvider: @unchecked Sendable, AppStoreActiveModeProviding {
    func currentActiveMode() -> WorkflowMode? { nil }
    func activeModeStream() -> AsyncStream<WorkflowMode?> {
        AsyncStream { continuation in continuation.finish() }
    }
}

private final class FakeVisibilityModeProvider: @unchecked Sendable, AppStoreVisibilityModeProviding {
    func currentVisibilityMode() -> AppStoreVisibilityMode { .alwaysOn }
    func visibilityModeStream() -> AsyncStream<AppStoreVisibilityMode> {
        AsyncStream { continuation in continuation.finish() }
    }
}
