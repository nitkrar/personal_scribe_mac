import XCTest
import SeshatCore
import SeshatSession
import SeshatTestSupport
@testable import SeshatAppKit

@MainActor
final class SeshatAppKitShellCompileTests: XCTestCase {
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
            logger: SeshatLogger(category: SeshatLogCategory.ui)
        )
        let app = SeshatApp(
            coordinator: coordinator,
            permissionRequester: TestShellPermissionRequester(),
            permissionStateProvider: { .granted },
            clipboardWriter: { _ in },
            openSettings: {}
        )

        _ = app.body
        XCTAssertNotNil(app)
    }
}

private struct TestShellPermissionRequester: MicrophonePermissionRequesting {
    func requestAccess() async -> Bool {
        true
    }
}
