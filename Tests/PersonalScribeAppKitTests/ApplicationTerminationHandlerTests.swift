import XCTest
@testable import PersonalScribeAppKit

@MainActor
final class ApplicationTerminationHandlerTests: XCTestCase {
    func testFastExitPrequitHandlerRunsGracefulShutdownBeforeLoggingAndExit() async {
        let recorder = EventRecorder()

        let handler = FastExitApplicationTerminationHandler.makePrequitHandler(
            stopIfActive: {
                recorder.append("stop:start")
                try? await Task.sleep(for: .milliseconds(1))
                recorder.append("stop:end")
            },
            shutdownPreparedWhisperCppAdapters: {
                recorder.append("shutdown:start")
                try? await Task.sleep(for: .milliseconds(1))
                recorder.append("shutdown:end")
            },
            logFastExit: { message in
                recorder.append("log:\(message)")
            },
            fastExit: {
                recorder.append("exit")
            }
        )

        await handler()

        XCTAssertEqual(
            recorder.snapshot(),
            [
                "stop:start",
                "stop:end",
                "shutdown:start",
                "shutdown:end",
                "log:application_terminating_via_fast_exit",
                "exit",
            ]
        )
    }
}

private final class EventRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [String] = []

    func append(_ event: String) {
        lock.withLock {
            events.append(event)
        }
    }

    func snapshot() -> [String] {
        lock.withLock {
            events
        }
    }
}
