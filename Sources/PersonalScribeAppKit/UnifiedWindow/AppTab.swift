import Foundation

/// Top-level tabs in the unified NavigationSplitView window.
///
/// Source of truth for sidebar navigation order and per-tab metadata
/// (display title + SF Symbol). `rawValue` doubles as the sidebar
/// label so tab rename requires a single edit.
///
/// Reference: `plans/App UI design/Claude_Final_Bundle_Prompt.md` §3
/// (4 nav tabs: Home / Transcriptions / Modes / Settings). `.about`
/// is routable but rendered as a sidebar footer row next to the
/// Microphone footer — see `sidebarListCases` for the regular-tab
/// subset consumed by `UnifiedWindowView`'s sidebar `List`.
public enum AppTab: String, CaseIterable, Identifiable, Sendable {
    case home           = "Home"
    case transcriptions = "Transcriptions"
    case modes          = "Modes"
    case settings       = "Settings"
    case about          = "About"

    public var id: String { rawValue }

    /// SF Symbol for the sidebar row icon.
    public var systemImageName: String {
        switch self {
        case .home:           return "house.fill"
        case .transcriptions: return "waveform"
        case .modes:          return "square.grid.2x2"
        case .settings:       return "gearshape"
        case .about:          return "info.circle"
        }
    }

    /// Tabs rendered as regular rows in the sidebar `List`. `.about`
    /// is intentionally excluded — it lives as a clickable footer row
    /// next to the Microphone footer (bug #1c, 2026-04-21 dogfood).
    public static let sidebarListCases: [AppTab] = [
        .home, .transcriptions, .modes, .settings,
    ]
}
