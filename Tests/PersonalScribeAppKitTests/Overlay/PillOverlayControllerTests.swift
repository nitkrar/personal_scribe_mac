import AppKit
import Combine
import XCTest
import PersonalScribeCore
@testable import PersonalScribeAppKit

@MainActor
final class PillOverlayControllerTests: XCTestCase {
    func testStreamCardStateChangesEmitObservabilityLogs() async throws {
        let appStore = try makeAppStore()
        let diagnosticsSink = InMemoryTestSink()
        let controller = PillOverlayController(
            appStore: appStore,
            defaults: .standard,
            panelBuilder: RecordingPanelBuilder(),
            diagnosticLogger: makeLogger(sink: diagnosticsSink)
        )
        _ = controller

        controller.applySnapshotForTesting(
            makeSnapshot(
                session: SessionSnapshot(
                    sessionState: .capturing,
                    transcriptProgress: TranscriptProgress(
                        revision: 1,
                        text: "hello",
                        isFinal: false,
                        sourceStage: .transcription
                    ),
                    isStreamingSession: true
                ),
                pillVisibility: .recording
            )
        )
        await settle()

        controller.applySnapshotForTesting(
            makeSnapshot(
                session: SessionSnapshot(
                    sessionState: .capturing,
                    transcriptProgress: TranscriptProgress(
                        revision: 2,
                        text: "hello world",
                        isFinal: false,
                        sourceStage: .transcription
                    ),
                    isStreamingSession: true
                ),
                pillVisibility: .recording
            )
        )
        await settle()

        controller.applySnapshotForTesting(
            makeSnapshot(
                session: SessionSnapshot(
                    sessionState: .transcribing,
                    transcriptProgress: nil,
                    isStreamingSession: true
                ),
                pillVisibility: .transcribing
            )
        )

        let messages = try await waitForStreamCardLogMessages(
            in: diagnosticsSink,
            expectedCount: 3
        )

        XCTAssertTrue(messages.contains { message in
            message.message.contains("action=show") &&
            message.message.contains("reason=new_text") &&
            message.message.contains("textLength=5") &&
            message.message.contains("sessionState=capturing") &&
            message.message.contains("isStreamingSession=true")
        })
        XCTAssertTrue(messages.contains { message in
            message.message.contains("action=update") &&
            message.message.contains("reason=text_changed") &&
            message.message.contains("textLength=11") &&
            message.message.contains("sessionState=capturing") &&
            message.message.contains("isStreamingSession=true")
        })
        XCTAssertTrue(messages.contains { message in
            message.message.contains("action=hide") &&
            message.message.contains("reason=recording_status_card_visible") &&
            message.message.contains("textLength=0") &&
            message.message.contains("sessionState=transcribing") &&
            message.message.contains("isStreamingSession=true")
        })
    }
}

@MainActor
private extension PillOverlayControllerTests {
    func makeAppStore() throws -> AppStore {
        let registry = try WorkflowModeRegistry(
            store: InMemoryWorkflowModeStore(),
            availableKindsProvider: { Set(ModelKind.allCases) }
        )
        return AppStore(
            session: FakeSessionProvider(),
            permissions: FakePermissionService(),
            workflowModeRegistry: registry,
            visibilityModeSource: FakeVisibilityModeProvider()
        )
    }

    func makeSnapshot(
        session: SessionSnapshot,
        pillVisibility: PillVisibilityState
    ) -> AppStoreSnapshot {
        AppStoreSnapshot(
            session: session,
            permissions: [
                .microphone: .granted,
                .inputMonitoring: .granted,
                .accessibility: .granted,
            ],
            activeMode: WorkflowMode.dictation,
            pillVisibility: pillVisibility,
            lastTranscriptionResult: nil,
            currentRecordingDuration: nil
        )
    }

    func makeLogger(sink: InMemoryTestSink) -> PersonalScribeLogger {
        PersonalScribeLogger(
            category: PersonalScribeLogCategory.ui,
            reporter: DiagnosticsReporter(
                sinks: [sink],
                now: { Date(timeIntervalSince1970: 0) }
            )
        )
    }

    func settle() async {
        for _ in 0..<5 {
            await Task.yield()
        }
    }

    func streamCardLogMessages(in sink: InMemoryTestSink) async -> [RedactedDiagnosticsEvent] {
        await sink.snapshot().filter {
            $0.message.contains("stream_card_state_changed")
        }
    }

    func waitForStreamCardLogMessages(
        in sink: InMemoryTestSink,
        expectedCount: Int,
        timeout: Duration = .seconds(2)
    ) async throws -> [RedactedDiagnosticsEvent] {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            let messages = await streamCardLogMessages(in: sink)
            if messages.count >= expectedCount {
                return messages
            }
            try await Task.sleep(for: .milliseconds(10))
        }

        let allMessages = await sink.snapshot().map(\.message)
        XCTFail(
            "Timed out waiting for \(expectedCount) stream-card diagnostics messages. Saw: \(allMessages)"
        )
        return await streamCardLogMessages(in: sink)
    }
}

@MainActor
private final class RecordingPanelBuilder: PillOverlayPanelBuilding {
    func makePanel(
        model: PillOverlayViewModel,
        panelSize: NSSize,
        onTap: @escaping @MainActor () -> Void,
        onMouseDragged: @escaping @MainActor () -> Void,
        isTapEnabled: @escaping @MainActor () -> Bool
    ) -> any PillOverlayPaneling {
        RecordingPanel(frame: NSRect(origin: .zero, size: panelSize))
    }
}

@MainActor
private final class RecordingPanel: PillOverlayPaneling {
    var isVisible = false
    var frame: NSRect
    let anchorWindow: NSWindow? = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 280, height: 60),
        styleMask: [.borderless],
        backing: .buffered,
        defer: false
    )

    init(frame: NSRect) {
        self.frame = frame
    }

    func orderFrontRegardless() {
        isVisible = true
    }

    func orderOut(_ sender: Any?) {
        isVisible = false
    }

    func setFrameOrigin(_ point: NSPoint) {
        frame.origin = point
    }

    func setFrame(_ frame: NSRect, animate: Bool) {
        self.frame = frame
    }
}

private final class FakeSessionProvider: @unchecked Sendable, AppStoreSessionProviding {
    private var currentSnapshot = SessionSnapshot()
    private var continuations: [UUID: AsyncStream<SessionSnapshot>.Continuation] = [:]

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

    func emit(_ snapshot: SessionSnapshot) {
        currentSnapshot = snapshot
        for continuation in continuations.values {
            continuation.yield(snapshot)
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

private final class FakeVisibilityModeProvider: @unchecked Sendable, AppStoreVisibilityModeProviding {
    func currentVisibilityMode() -> AppStoreVisibilityMode { .alwaysOn }

    func visibilityModeStream() -> AsyncStream<AppStoreVisibilityMode> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }
}
