import AppKit

@MainActor
enum PasteRoutingDecision: Equatable, Sendable {
    enum ClipboardOnlyReason: Equatable, Sendable {
        case clipboardOnlyMode
        case frontmostAppIsSeshat
    }

    case pasteAtCursor
    case clipboardOnly(reason: ClipboardOnlyReason)
}

@MainActor
protocol FrontmostAppProviding {
    var frontmostApplicationBundleIdentifier: String? { get }
}

struct WorkspaceFrontmostAppProvider: FrontmostAppProviding {
    var frontmostApplicationBundleIdentifier: String? {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    }
}
