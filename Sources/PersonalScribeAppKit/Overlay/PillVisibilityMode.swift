import Foundation
import PersonalScribeCore

/// User-selectable visibility mode for the pill overlay.
///
/// Reference: `plans/seshat_agent_bundle/03_Surfaces/PillOverlayWindow/architecture.png`
/// shows the three rows — Always On / Auto-show / Hidden. This enum is the
/// canonical representation.
///
/// ## Semantics
/// * **`.alwaysOn`** — the pill is visible at all times (Mode 1 row). It
///   shows the idle quill + flat wave when there is no active session,
///   swaps to the recording layout during recording, and remains visible
///   between sessions.
/// * **`.autoShow` (default)** — the pill appears only while a
///   recording / transcription / download is in flight, and fades back
///   out when idle. The menu bar is the always-visible surface.
/// * **`.hidden`** — the pill never shows; the menu bar + hotkeys are
///   the only user-reachable surfaces. Invariant: at least one of
///   `hidden` pill / `hidden` menu bar must be false — the menu bar
///   cannot ship a "hide" toggle while pill is `.hidden`. Phase 2 has
///   no menu-bar-hide toggle, so the invariant holds by construction
///   (see PLAN_PHASES.md line 293).
///
/// ## Persistence
/// Stored in `UserDefaults` at `PillVisibilityMode`. On first
/// launch (key absent), the default is `.autoShow`, matching the mockup
/// row labelled "Mode 2 — Auto-show (default)".
public enum PillVisibilityMode: String, CaseIterable, Codable, Sendable, Equatable {
    case alwaysOn = "always-on"
    case autoShow = "auto-show"
    case hidden

    /// The UserDefaults key used across the app. Centralised here so
    /// the Phase 3 Settings UI and the Phase 2 pill overlay agree on
    /// exactly one string.
    public static let `default`: Self = .autoShow
    public static let userDefaultsKey = "PillVisibilityMode"

    public static func preference(defaults: UserDefaults = .standard) -> Preference<Self> {
        Preference(key: userDefaultsKey, default: .default, defaults: defaults)
    }

    /// Resolve the currently persisted mode, falling back to
    /// `.autoShow` if the key is missing or holds an unrecognised
    /// value (defensive: an older build might have written a legacy
    /// string).
    public static func resolve(from defaults: UserDefaults = .standard) -> PillVisibilityMode {
        preference(defaults: defaults).resolve()
    }

    /// Persist the current mode. Calling `.persist(to:)` is equivalent
    /// to `defaults.set(rawValue, forKey: userDefaultsKey)` but keeps
    /// the key-name plumbing contained in this type.
    public func persist(to defaults: UserDefaults = .standard) {
        Self.preference(defaults: defaults).persist(self)
    }
}
