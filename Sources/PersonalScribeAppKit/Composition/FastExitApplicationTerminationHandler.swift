import PersonalScribeCore
import os

enum FastExitApplicationTerminationHandler {
    typealias AsyncAction = @MainActor @Sendable () async -> Void
    typealias LogAction = @MainActor @Sendable (String) -> Void
    typealias ExitAction = @Sendable () -> Void

    static let fastExitLogMessage = "application_terminating_via_fast_exit"

    static func makePrequitHandler(
        stopIfActive: @escaping AsyncAction,
        shutdownPreparedWhisperCppAdapters: @escaping AsyncAction,
        logFastExit: @escaping LogAction = defaultLogFastExit(_:),
        fastExit: @escaping ExitAction = defaultFastExit
    ) -> AsyncAction {
        {
            await stopIfActive()
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

    private static func defaultFastExit() {
        Darwin._exit(0)
    }
}
