import Foundation

/// Top-level tabs in the unified NavigationSplitView window.
///
/// Source of truth for sidebar navigation order and per-tab metadata
/// (display title + SF Symbol). `rawValue` doubles as the sidebar
/// label so tab rename requires a single edit.
///
/// Reference: `plans/App UI design/Claude_Final_Bundle_Prompt.md` §3
/// (4 tabs: Home / Transcriptions / Modes / Settings).
public enum AppTab: String, CaseIterable, Identifiable, Sendable {
    case home           = "Home"
    case transcriptions = "Transcriptions"
    case modes          = "Modes"
    case settings       = "Settings"

    public var id: String { rawValue }

    /// SF Symbol for the sidebar row icon.
    public var systemImageName: String {
        switch self {
        case .home:           return "house.fill"
        case .transcriptions: return "text.alignleft"
        case .modes:          return "square.grid.2x2"
        case .settings:       return "gearshape"
        }
    }
}
