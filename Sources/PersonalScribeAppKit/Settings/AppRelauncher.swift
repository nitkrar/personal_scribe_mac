import AppKit
import Foundation
import PersonalScribeCore

/// Utility that relaunches the running app. Used by "Restart required"
/// Settings surfaces where a preference change only takes effect on the
/// next launch (background-mode activation policy, recording-hotkey
/// registration, future similarly-gated settings).
///
/// Mechanism: ask `NSWorkspace` to launch a fresh instance of the app
/// bundle with `createsNewApplicationInstance = true` so the OS spawns
/// a second process instead of reactivating the current one, then call
/// `NSApp.terminate(nil)` once the open completes. Both steps are needed
/// — without the new-instance flag, `openApplication` just reactivates
/// the current process and we never restart.
///
/// The open-completion callback can run on an arbitrary queue; we hop
/// back to the main actor to terminate so AppKit state is drained
/// cleanly. Any error is logged and the terminate is skipped, leaving
/// the current process alive (the user can retry or restart manually).
@MainActor
public enum AppRelauncher {
    public static func relaunch(logger: PersonalScribeLogger) {
        let url = Bundle.main.bundleURL
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: url, configuration: config) { _, error in
            if let error {
                logger.error("AppRelauncher: openApplication failed", error: error)
                return
            }
            Task { @MainActor in
                NSApp.terminate(nil)
            }
        }
    }
}
