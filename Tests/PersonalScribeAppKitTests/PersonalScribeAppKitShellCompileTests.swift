import Combine
import XCTest
import PersonalScribeCore
import PersonalScribeSession
import PersonalScribeTestSupport
@testable import PersonalScribeAppKit

@MainActor
final class PersonalScribeAppKitShellCompileTests: XCTestCase {
    func testShellCompiles() throws {
        let coordinator = SessionCoordinator(
            capture: FakeAudioCapturing(buffers: [try PCMBuffer(samples: [0.25], timestamp: ContinuousClock().now)]),
            transcriber: FakeTranscriber(
                result: TranscriptionResult(
                    text: "shell",
                    audioDuration: .seconds(1),
                    processingDuration: .milliseconds(50)
                )
            ),
            logger: PersonalScribeLogger(category: PersonalScribeLogCategory.ui)
        )
        let app = PersonalScribeApp(
            coordinator: coordinator,
            permissionService: FakePermissionService(),
            clipboardWriter: { _ in },
            openSettings: {}
        )

        _ = app.body
        XCTAssertNotNil(app)
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
