import CoreGraphics
import Foundation
import PersonalScribeCore

/// User-selectable pill *shape* preference — independent of
/// `PillAppearance` (dark/light tokens) and `PillVisibility`
/// (when the pill is shown at all).
///
/// Two variants:
/// * `.classic` — full pill with voice-modulated waveform (default).
/// * `.mini`    — the classic pill at `scale`.
public enum PillStyle: String, CaseIterable, Identifiable, Codable, Sendable, StoredPreference {
    case classic = "Classic"
    case mini    = "Mini"

    public var id: String { rawValue }

    public static let setting = SettingKey<PillStyle>(key: "PillStyle", default: .classic)

    public func persist(to defaults: UserDefaults = .standard) {
        Self.persist(self, to: defaults)
    }

    /// Size multiplier applied to every pill state.
    public var scale: CGFloat {
        self == .mini ? 0.75 : 1
    }
}
