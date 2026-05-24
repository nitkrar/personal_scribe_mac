import AppKit
import Combine
import XCTest
import PersonalScribeCore
@testable import PersonalScribeAppKit

@MainActor
final class PillOverlayControllerTests: XCTestCase {
    func testStreamCardShownAndHiddenEmitObservabilityLogs() async throws {
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

        // Expect exactly 2 log lines: one `stream_card_shown` at first
        // visibility, one `stream_card_hidden` with an updates summary at
        // teardown. Per-update text changes do NOT log (used to spam at
        // ~30/session; now aggregated into the hidden line's
        // updatesSinceShow + maxTextLength fields).
        let messages = try await waitForStreamCardLogMessages(
            in: diagnosticsSink,
            expectedCount: 2
        )

        XCTAssertEqual(messages.count, 2, "Expected exactly 2 stream-card log lines, got: \(messages.map(\.message))")

        XCTAssertTrue(messages.contains { message in
            message.message.contains("stream_card_shown") &&
            message.message.contains("initialTextLength=5") &&
            message.message.contains("sessionState=capturing") &&
            message.message.contains("isStreamingSession=true")
        }, "Expected stream_card_shown with initialTextLength=5; saw: \(messages.map(\.message))")

        XCTAssertTrue(messages.contains { message in
            message.message.contains("stream_card_hidden") &&
            message.message.contains("reason=recording_status_card_visible") &&
            message.message.contains("updatesSinceShow=1") &&
            message.message.contains("finalTextLength=11") &&
            message.message.contains("maxTextLength=11") &&
            message.message.contains("sessionState=transcribing") &&
            message.message.contains("isStreamingSession=true")
        }, "Expected stream_card_hidden with updates summary; saw: \(messages.map(\.message))")
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
            $0.message.contains("stream_card_shown") || $0.message.contains("stream_card_hidden")
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
