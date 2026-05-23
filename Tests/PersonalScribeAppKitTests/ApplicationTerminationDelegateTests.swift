import XCTest
@testable import PersonalScribeAppKit

@MainActor
final class ApplicationTerminationDelegateTests: XCTestCase {
    func testInterceptTerminationRequestReturnsTerminateLaterAndRepliesFalseIfHandlerReturns() async {
        let recorder = EventRecorder()
        let scheduler = PendingTerminationScheduler()
        let delegate = FastExitApplicationTerminationDelegate(
            replyToApplicationShouldTerminate: { shouldTerminate in
                recorder.append("reply:\(shouldTerminate)")
            },
            scheduleTermination: { action in
                scheduler.enqueue(action)
            }
        )
        delegate.installPrequitHandler {
            recorder.append("prequit:start")
            try? await Task.sleep(for: .milliseconds(1))
            recorder.append("prequit:end")
        }

        XCTAssertEqual(delegate.interceptTerminationRequest(), .terminateLater)
        XCTAssertEqual(scheduler.pendingCount, 1)

        await scheduler.runNext()

        XCTAssertEqual(
            recorder.snapshot(),
            [
                "prequit:start",
                "prequit:end",
                "reply:false",
            ]
        )
    }

    func testInterceptTerminationRequestCoalescesConcurrentRequestsUntilHandlerReturns() async {
        let recorder = EventRecorder()
        let scheduler = PendingTerminationScheduler()
        let gate = AsyncGate()
        let delegate = FastExitApplicationTerminationDelegate(
            replyToApplicationShouldTerminate: { shouldTerminate in
                recorder.append("reply:\(shouldTerminate)")
            },
            scheduleTermination: { action in
                scheduler.enqueue(action)
            }
        )
        delegate.installPrequitHandler {
            recorder.append("prequit:start")
            await gate.wait()
            recorder.append("prequit:end")
        }

        XCTAssertEqual(delegate.interceptTerminationRequest(), .terminateLater)
        XCTAssertEqual(delegate.interceptTerminationRequest(), .terminateLater)
        XCTAssertEqual(scheduler.pendingCount, 1)

        let inFlight = Task { @MainActor in
            await scheduler.runNext()
        }
        await Task.yield()

        XCTAssertEqual(delegate.interceptTerminationRequest(), .terminateLater)
        XCTAssertEqual(scheduler.pendingCount, 0)

        await gate.open()
        await inFlight.value

        XCTAssertEqual(
            recorder.snapshot(),
            [
                "prequit:start",
                "prequit:end",
                "reply:false",
            ]
        )

        XCTAssertEqual(delegate.interceptTerminationRequest(), .terminateLater)
        XCTAssertEqual(scheduler.pendingCount, 1)
    }
}

@MainActor
private final class PendingTerminationScheduler {
    typealias Action = @MainActor @Sendable () async -> Void

    private var pendingActions: [Action] = []

    var pendingCount: Int {
        pendingActions.count
    }

    func enqueue(_ action: @escaping Action) {
        pendingActions.append(action)
    }

    func runNext() async {
        let action = pendingActions.removeFirst()
        await action()
    }
}

private actor AsyncGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var isOpen = false

    func wait() async {
        guard !isOpen else {
            return
        }

        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func open() {
        isOpen = true
        continuation?.resume()
        continuation = nil
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
