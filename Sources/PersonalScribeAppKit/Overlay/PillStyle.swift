import Foundation
import PersonalScribeCore

/// User-selectable pill *shape* preference — independent of
/// `PillAppearance` (dark/light tokens) and `PillVisibility`
/// (when the pill is shown at all).
///
/// Three variants:
/// * `.classic` — full pill with voice-modulated waveform (default).
/// * `.mini`    — compact flat pill, no inline content.
/// * `.none`    — pill hidden regardless of `PillVisibility`.
///
/// Reference: `plans/App UI design/final_settings_general_v2.png`
/// RECORDING WINDOW section. The Settings UI that sets this
/// preference landed in mockup-gaps D.1 (2026-04-21); the downstream
/// wiring to `PillOverlayView` rendering is deferred — tracked in
/// `plans/backlog/ui-mockup-gaps.md`.
public enum PillStyle: String, CaseIterable, Identifiable, Codable, Sendable, StoredPreference {
    case classic = "Classic"
    case mini    = "Mini"
    case none    = "None"

    public var id: String { rawValue }

    public static let setting = SettingKey<PillStyle>(key: "PillStyle", default: .classic)

    public func persist(to defaults: UserDefaults = .standard) {
        Self.persist(self, to: defaults)
    }
}
