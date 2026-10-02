import Dispatch
import Foundation
import PersonalScribeCore
import os

enum FastExitApplicationTerminationHandler {
    typealias AsyncAction = @MainActor @Sendable () async -> Void
    typealias LogAction = @MainActor @Sendable (String) -> Void
    typealias DeadlineLogAction = @Sendable (String) -> Void
    typealias ExitAction = @Sendable () -> Void
    typealias ScheduleDeadlineAction = @MainActor (Duration, @escaping @Sendable () -> Void) -> Void

    static let fastExitLogMessage = "application_terminating_via_fast_exit"
    static let shutdownDeadline: Duration = .seconds(3)

    /// Graceful shutdown with a hard deadline. If a step hangs (e.g. a
    /// wedged session pipeline), the deadline fires off the main actor —
    /// which may itself be stuck — logs the pending step and exits.
    static func makePrequitHandler(
        stopIfActive: @escaping AsyncAction,
        shutdownPreparedWhisperCppAdapters: @escaping AsyncAction,
        logFastExit: @escaping LogAction = defaultLogFastExit(_:),
        logDeadlineExceeded: @escaping DeadlineLogAction = defaultLogDeadlineExceeded(_:),
        fastExit: @escaping ExitAction = defaultFastExit,
        scheduleDeadline: @escaping ScheduleDeadlineAction = defaultScheduleDeadline(_:_:)
    ) -> AsyncAction {
        {
            let stage = ShutdownStage("stopIfActive")
            scheduleDeadline(shutdownDeadline) {
                logDeadlineExceeded("fast_exit_deadline_exceeded stage=\(stage.current)")
                fastExit()
            }
            await stopIfActive()
            stage.current = "shutdownPreparedWhisperCppAdapters"
            await shutdownPreparedWhisperCppAdapters()
            logFastExit(fastExitLogMessage)
            fastExit()
        }
    }

    // Use a direct OSLog write here: the normal diagnostics fanout is
    // asynchronous and may not flush before `_exit(0)` terminates the process.
    private static func defaultLogFastExit(_ message: String) {
        Logger(
            subsystem: PersonalScribeLogger.subsystem,
            category: PersonalScribeLogCategory.app
        ).info("\(message, privacy: .public)")
    }

    private static func defaultLogDeadlineExceeded(_ message: String) {
        Logger(
            subsystem: PersonalScribeLogger.subsystem,
            category: PersonalScribeLogCategory.app
        ).error("\(message, privacy: .public)")
    }

    private static func defaultFastExit() {
        Darwin._exit(0)
    }

    private static func defaultScheduleDeadline(
        _ delay: Duration,
        _ action: @escaping @Sendable () -> Void
    ) {
        let (seconds, attoseconds) = delay.components
        let nanoseconds = Int(seconds) * 1_000_000_000 + Int(attoseconds / 1_000_000_000)
        DispatchQueue.global(qos: .userInitiated).asyncAfter(
            deadline: .now() + .nanoseconds(nanoseconds),
            execute: action
        )
    }
}

/// Shutdown step the prequit handler is currently awaiting. Read from
/// the deadline's background queue, written from the main actor.
private final class ShutdownStage: @unchecked Sendable {
    private let lock = NSLock()
    private var value: String

    init(_ initial: String) {
        value = initial
    }

    var current: String {
        get { lock.withLock { value } }
        set { lock.withLock { value = newValue } }
    }
}
