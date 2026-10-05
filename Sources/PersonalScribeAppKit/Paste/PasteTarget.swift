import AppKit
import PersonalScribeCore

/// Where a synthetic Cmd+V will land. Shared by batch paste
/// (`ClipboardBatchOutput`) and live cursor output (`LiveCursorOutput`).
/// Paste into another frontmost app, or into Ninimma only when its
/// in-process first responder is a text input. Otherwise leave the
/// transcript on the clipboard.
enum PasteTarget: Equatable {
    case frontmost(bundleID: String?, pid: pid_t, appName: String? = nil)
    case ownTextInput
    case noFrontmostApp

    func permitsPaste(selfBundleID: String) -> Bool {
        switch self {
        case .frontmost(let bundleID, _, _):
            return bundleID != selfBundleID
        case .ownTextInput:
            return true
        case .noFrontmostApp:
            return false
        }
    }

    var logDescription: String {
        switch self {
        case .frontmost(let bundleID, let pid, _):
            return "frontmost=\(bundleID ?? "nil") pid=\(pid)"
        case .ownTextInput:
            return "frontmost=self target=text-input"
        case .noFrontmostApp:
            return "frontmost=none"
        }
    }

    /// Name stored as the transcript's destination (#117).
    var destinationAppName: String {
        switch self {
        case .frontmost(let bundleID, _, let appName):
            return appName ?? bundleID ?? "Unknown"
        case .ownTextInput:
            return AppBrand.displayName
        case .noFrontmostApp:
            return "Unknown"
        }
    }

    static func resolve(
        frontmostBundleID: String?,
        frontmostPID: pid_t,
        frontmostAppName: String? = nil,
        currentPID: pid_t,
        hasOwnTextInputFocus: Bool
    ) -> PasteTarget {
        if frontmostPID == currentPID && hasOwnTextInputFocus {
            return .ownTextInput
        }
        return .frontmost(bundleID: frontmostBundleID, pid: frontmostPID, appName: frontmostAppName)
    }

    @MainActor
    static func live() -> PasteTarget {
        guard let app = NSWorkspace.shared.frontmostApplication else { return .noFrontmostApp }
        return resolve(
            frontmostBundleID: app.bundleIdentifier,
            frontmostPID: app.processIdentifier,
            frontmostAppName: app.localizedName,
            currentPID: ProcessInfo.processInfo.processIdentifier,
            hasOwnTextInputFocus: hasEditableTextInputFocus(in: NSApp.keyWindow)
        )
    }

    @MainActor
    static func hasEditableTextInputFocus(in window: NSWindow?) -> Bool {
        guard let text = window?.firstResponder as? NSText, text.isEditable else {
            return false
        }
        guard let textView = text as? NSTextView else {
            return true
        }
        return !(textView.isFieldEditor && textView.delegate is NSSecureTextField)
    }
}
