import AppKit

@MainActor
final class FastExitApplicationTerminationDelegate: NSObject, NSApplicationDelegate {
    typealias AsyncAction = @MainActor @Sendable () async -> Void
    typealias ReplyAction = @MainActor @Sendable (Bool) -> Void
    typealias ScheduleAction = @MainActor @Sendable (@escaping AsyncAction) -> Void

    private var prequitHandler: AsyncAction = {}
    private let replyToApplicationShouldTerminate: ReplyAction
    private let scheduleTermination: ScheduleAction
    private var terminationInterceptionInFlight = false

    init(
        replyToApplicationShouldTerminate: @escaping ReplyAction = {
            NSApplication.shared.reply(toApplicationShouldTerminate: $0)
        },
        scheduleTermination: @escaping ScheduleAction = defaultScheduleTermination(_:)
    ) {
        self.replyToApplicationShouldTerminate = replyToApplicationShouldTerminate
        self.scheduleTermination = scheduleTermination
    }

    func installPrequitHandler(_ handler: @escaping AsyncAction) {
        prequitHandler = handler
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        interceptTerminationRequest()
    }

    func interceptTerminationRequest() -> NSApplication.TerminateReply {
        guard !terminationInterceptionInFlight else {
            return .terminateLater
        }

        terminationInterceptionInFlight = true
        let prequitHandler = self.prequitHandler
        let replyToApplicationShouldTerminate = self.replyToApplicationShouldTerminate

        scheduleTermination { [weak self] in
            await prequitHandler()
            self?.terminationInterceptionInFlight = false
            // `_exit(0)` should make this unreachable in production. If a
            // test double or unexpected integration lets the handler return,
            // cancel AppKit termination rather than falling through to the
            // C++ atexit path that still crashes whisper.cpp.
            replyToApplicationShouldTerminate(false)
        }

        return .terminateLater
    }

    private static func defaultScheduleTermination(_ action: @escaping AsyncAction) {
        Task { @MainActor in
            await action()
        }
    }
}
