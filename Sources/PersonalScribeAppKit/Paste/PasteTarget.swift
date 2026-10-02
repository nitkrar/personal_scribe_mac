import AppKit

/// Where a synthetic Cmd+V will land: the frontmost app. Shared by batch
/// paste (`ClipboardBatchOutput`) and live cursor output
/// (`LiveCursorOutput`).
///
/// The rule is deliberately simple — paste unless Ninimma itself is
/// frontmost. An earlier AX focused-element check never verified a text
/// cursor (it only compared PIDs) and failed outright for Electron apps
/// (Slack) that hide their AX tree, skipping the paste.
enum PasteTarget: Equatable {
    case frontmost(bundleID: String?, pid: pid_t)
    case noFrontmostApp

    func permitsPaste(selfBundleID: String) -> Bool {
        switch self {
        case .frontmost(let bundleID, _):
            return bundleID != selfBundleID
        case .noFrontmostApp:
            return false
        }
    }

    var logDescription: String {
        switch self {
        case .frontmost(let bundleID, let pid):
            return "frontmost=\(bundleID ?? "nil") pid=\(pid)"
        case .noFrontmostApp:
            return "frontmost=none"
        }
    }

    @MainActor
    static func live() -> PasteTarget {
        guard let app = NSWorkspace.shared.frontmostApplication else { return .noFrontmostApp }
        return .frontmost(bundleID: app.bundleIdentifier, pid: app.processIdentifier)
    }
}
