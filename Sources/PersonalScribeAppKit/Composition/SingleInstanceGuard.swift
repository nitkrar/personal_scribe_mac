import AppKit
import Foundation

/// Enforces one running copy per bundle identifier. A second launch
/// (Finder double-click, `open`, login item racing a manual start)
/// activates the existing copy and exits before any composition work
/// runs. Relaunch stays compatible because `AppRelauncher` only opens
/// the new copy after the old process has exited.
enum SingleInstanceGuard {
    struct Instance: Equatable {
        let pid: pid_t
        let isTerminated: Bool
    }

    static func otherInstance(in running: [Instance], currentPID: pid_t) -> Instance? {
        running.first { $0.pid != currentPID && !$0.isTerminated }
    }

    /// Exits the process if another live copy is already running.
    /// No-op for unbundled builds (`swift run`), which have no bundle id.
    @MainActor
    static func exitIfAnotherInstanceIsRunning() {
        guard let bundleID = Bundle.main.bundleIdentifier else { return }
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        let instances = apps.map { Instance(pid: $0.processIdentifier, isTerminated: $0.isTerminated) }
        guard let other = otherInstance(
            in: instances,
            currentPID: ProcessInfo.processInfo.processIdentifier
        ) else { return }
        apps.first { $0.processIdentifier == other.pid }?.activate()
        exit(0)
    }
}
