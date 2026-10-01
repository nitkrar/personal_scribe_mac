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
            },
            scheduleDeadline: { _, _ in }
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

    func testFastExitPrequitHandlerForcesExitWhenShutdownStepExceedsDeadline() async {
        let recorder = EventRecorder()
        var scheduledDelay: Duration?
        var fireDeadline: (@Sendable () -> Void)?

        let handler = FastExitApplicationTerminationHandler.makePrequitHandler(
            stopIfActive: {
                recorder.append("stop:start")
                try? await Task.sleep(for: .seconds(60))
                recorder.append("stop:end")
            },
            shutdownPreparedWhisperCppAdapters: {
                recorder.append("shutdown:start")
            },
            logFastExit: { message in
                recorder.append("log:\(message)")
            },
            logDeadlineExceeded: { message in
                recorder.append("deadline:\(message)")
            },
            fastExit: {
                recorder.append("exit")
            },
            scheduleDeadline: { delay, action in
                scheduledDelay = delay
                fireDeadline = action
            }
        )

        let quit = Task { await handler() }
        while !recorder.snapshot().contains("stop:start") {
            await Task.yield()
        }

        XCTAssertEqual(scheduledDelay, .seconds(3))
        fireDeadline?()

        XCTAssertEqual(
            recorder.snapshot(),
            [
                "stop:start",
                "deadline:fast_exit_deadline_exceeded stage=stopIfActive",
                "exit",
            ]
        )
        quit.cancel()
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
