import Foundation
import SwiftUI
import PersonalScribeCore

/// User-selectable main-window background tint (light-mode brand flavor).
///
/// Two variants:
/// * `.warm`    — paper/editorial cream (`#F5F5F0` / `#EBEBE6`). Default.
/// * `.neutral` — native macOS grey (`#F2F2F7` / `#E8E8ED`).
///
/// `WindowTint` is a light-mode-only brand flavor. The app's master
/// light/dark switch lives on `AppTheme` (Light / Dark / System). The
/// previous `.dark` case — which did double duty as a tint flavor AND
/// a dark-aqua `NSAppearance` override — was removed as part of
/// mockup-gaps G (2026-04-21). For dark rendering use `AppTheme.dark`.
///
/// No migration shim for the retired `.dark` raw value: a persisted
/// `"WindowTint" == "Dark"` silently falls back to `.warm` via the
/// `resolve` unrecognised-raw-value path.
public enum WindowTint: String, CaseIterable, Identifiable, Codable, Sendable, StoredPreference {
    case warm    = "Warm"
    case neutral = "Neutral"

    public var id: String { rawValue }

    public static let setting = SettingKey<WindowTint>(key: "WindowTint", default: .warm)

    public func persist(to defaults: UserDefaults = .standard) {
        Self.persist(self, to: defaults)
    }

    // MARK: - Semantic backgrounds

    /// Primary content-area background.
    public var primaryBackground: Color {
        switch self {
        case .warm:    return PersonalScribeTheme.color(hex: "F5F5F0")
        case .neutral: return PersonalScribeTheme.color(hex: "F2F2F7")
        }
    }

    /// Sidebar / secondary-area background.
    public var secondaryBackground: Color {
        switch self {
        case .warm:    return PersonalScribeTheme.color(hex: "EBEBE6")
        case .neutral: return PersonalScribeTheme.color(hex: "E8E8ED")
        }
    }

    /// Card / row surface.
    public var cardBackground: Color {
        switch self {
        case .warm, .neutral: return PersonalScribeTheme.color(hex: "FFFFFF")
        }
    }

    /// Hover / pressed-state surface.
    public var hoverBackground: Color {
        switch self {
        case .warm:    return PersonalScribeTheme.color(hex: "DCDCD7")
        case .neutral: return PersonalScribeTheme.color(hex: "DCDCE0")
        }
    }

    /// Primary text colour (solid — caller applies opacity if needed).
    public var primaryText: Color {
        switch self {
        case .warm, .neutral: return PersonalScribeTheme.color(hex: "1C1C1E")
        }
    }
}

// MARK: - WindowTint environment bridge
//
// The tint is installed at the unified-window root (see
// `UnifiedWindowView.swift`) and read by any descendant surface that
// needs warm/neutral-aware card backgrounds or accent swaps. Views
// that don't care (previews, unit-test harnesses without a tint) see
// `nil` and fall back to `PersonalScribeTheme.Palette.for(scheme:)`.

public struct WindowTintEnvironmentKey: EnvironmentKey {
    public static let defaultValue: WindowTint? = nil
}

extension EnvironmentValues {
    public var windowTint: WindowTint? {
        get { self[WindowTintEnvironmentKey.self] }
        set { self[WindowTintEnvironmentKey.self] = newValue }
    }
}

extension View {
    /// Install a `WindowTint` in the environment so descendant surfaces
    /// (stat cards, settings cards, mode cards, etc.) pick up matching
    /// card / hover / accent values via
    /// `PersonalScribeTheme.Palette.for(scheme:tint:)`.
    public func windowTint(_ tint: WindowTint) -> some View {
        environment(\.windowTint, tint)
    }
}
