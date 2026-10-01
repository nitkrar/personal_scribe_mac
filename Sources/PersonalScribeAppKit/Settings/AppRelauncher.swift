import AppKit
import Foundation
import PersonalScribeCore

/// Utility that relaunches the running app. Used by "Restart required"
/// Settings surfaces where a preference change only takes effect on the
/// next launch (background-mode activation policy, recording-hotkey
/// registration, future similarly-gated settings).
///
/// Mechanism: spawn a detached helper shell that waits for this process
/// to exit and then `open`s the app bundle, then `NSApp.terminate(nil)`.
/// Quit-first ordering means there is never a second copy alive next to
/// one that's still shutting down; the termination handler's deadline
/// guarantees the wait ends. If the helper can't be spawned, the error
/// is logged and the terminate is skipped, leaving the current process
/// alive (the user can retry or restart manually).
@MainActor
public enum AppRelauncher {
    public static func relaunch(logger: PersonalScribeLogger) {
        do {
            try spawnRelaunchHelper(
                waitingFor: ProcessInfo.processInfo.processIdentifier,
                appURL: Bundle.main.bundleURL
            )
        } catch {
            logger.error("AppRelauncher: relaunch helper failed to spawn", error: error)
            return
        }
        NSApp.terminate(nil)
    }

    @discardableResult
    nonisolated static func spawnRelaunchHelper(
        waitingFor pid: pid_t,
        appURL: URL,
        opener: String = "/usr/bin/open"
    ) throws -> Process {
        let helper = Process()
        helper.executableURL = URL(fileURLWithPath: "/bin/sh")
        helper.arguments = [
            "-c",
            "while kill -0 \"$1\" 2>/dev/null; do sleep 0.1; done; exec \"$2\" \"$3\"",
            "relaunch-helper",
            String(pid),
            opener,
            appURL.path,
        ]
        try helper.run()
        return helper
    }
}
