import CoreGraphics
import Foundation
import PersonalScribeCore

/// User-selectable pill *shape* preference — independent of
/// `PillAppearance` (dark/light tokens) and `PillVisibility`
/// (when the pill is shown at all).
///
/// Three variants:
/// * `.classic` — full pill with voice-modulated waveform (default).
/// * `.mini`    — compact state-specific layouts for idle, recording, and pause.
/// * `.none`    — the pill never shows; record from the shortcut or menu bar.
public enum PillStyle: String, CaseIterable, Identifiable, Codable, Sendable, StoredPreference {
    case classic = "Classic"
    case mini    = "Mini"
    case none    = "None"

    public var id: String { rawValue }

    public static let setting = SettingKey<PillStyle>(key: "PillStyle", default: .classic)

    public func persist(to defaults: UserDefaults = .standard) {
        Self.persist(self, to: defaults)
    }

    /// Fallback multiplier for auxiliary states without a dedicated Mini layout.
    public var scale: CGFloat {
        self == .mini ? 0.75 : 1
    }
}
