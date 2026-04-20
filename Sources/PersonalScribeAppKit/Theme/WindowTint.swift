import Foundation
import SwiftUI

/// User-selectable main-window background tint.
///
/// Three variants:
/// * `.warm`    — paper/editorial cream (`#F5F5F0` / `#EBEBE6`). Default.
/// * `.neutral` — native macOS grey (`#F2F2F7` / `#E8E8ED`).
/// * `.dark`    — forces dark palette (`#0E0E14` / `#111318`) regardless
///                of the user's system light/dark setting.
///
/// Persisted under `UserDefaults` key `"WindowTint"`. Per the project
/// convention, UserDefaults keys are bundle-scoped (the
/// `com.nitkrar.personal_scribe` domain already namespaces them) so
/// the raw key has no `PersonalScribe*` prefix.
///
/// Reference: `plans/App UI design/Claude_Final_Bundle_Prompt.md` §1
/// and the `SeshatTheme.swift` drop-in (`WindowTint` adopted verbatim;
/// type is namespace-free per the project naming rule).
public enum WindowTint: String, CaseIterable, Identifiable, Sendable {
    case warm    = "Warm"
    case neutral = "Neutral"
    case dark    = "Dark"

    public var id: String { rawValue }

    /// UserDefaults key. Unprefixed by design — bundle-scoped already.
    public static let userDefaultsKey = "WindowTint"

    /// Reads the persisted tint, falling back to `.warm` when absent
    /// or the stored value is not a recognised case.
    public static func resolve(from defaults: UserDefaults = .standard) -> WindowTint {
        guard let raw = defaults.string(forKey: userDefaultsKey),
              let value = WindowTint(rawValue: raw) else {
            return .warm
        }
        return value
    }

    /// Writes the tint's raw value to defaults.
    public func persist(to defaults: UserDefaults = .standard) {
        defaults.set(rawValue, forKey: Self.userDefaultsKey)
    }

    /// `true` only for `.dark` — consumer windows should apply
    /// `NSAppearance(named: .darkAqua)` regardless of the system theme.
    public var forcesDarkMode: Bool { self == .dark }

    // MARK: - Semantic backgrounds

    /// Primary content-area background.
    public var primaryBackground: Color {
        switch self {
        case .warm:    return PersonalScribeTheme.color(hex: "F5F5F0")
        case .neutral: return PersonalScribeTheme.color(hex: "F2F2F7")
        case .dark:    return PersonalScribeTheme.color(hex: "0E0E14")
        }
    }

    /// Sidebar / secondary-area background.
    public var secondaryBackground: Color {
        switch self {
        case .warm:    return PersonalScribeTheme.color(hex: "EBEBE6")
        case .neutral: return PersonalScribeTheme.color(hex: "E8E8ED")
        case .dark:    return PersonalScribeTheme.color(hex: "111318")
        }
    }

    /// Card / row surface.
    public var cardBackground: Color {
        switch self {
        case .warm, .neutral: return PersonalScribeTheme.color(hex: "FFFFFF")
        case .dark:           return PersonalScribeTheme.color(hex: "1C1C1E")
        }
    }

    /// Hover / pressed-state surface.
    public var hoverBackground: Color {
        switch self {
        case .warm:    return PersonalScribeTheme.color(hex: "DCDCD7")
        case .neutral: return PersonalScribeTheme.color(hex: "DCDCE0")
        case .dark:    return PersonalScribeTheme.color(hex: "2A2A30")
        }
    }

    /// Primary text colour (solid — caller applies opacity if needed).
    public var primaryText: Color {
        switch self {
        case .warm, .neutral: return PersonalScribeTheme.color(hex: "1C1C1E")
        case .dark:           return PersonalScribeTheme.color(hex: "F2F2F7")
        }
    }
}
