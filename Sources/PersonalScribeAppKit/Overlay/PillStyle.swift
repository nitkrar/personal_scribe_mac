import CoreGraphics
import Foundation
import PersonalScribeCore

/// User-selectable pill *shape* preference — independent of
/// `PillAppearance` (dark/light tokens) and `PillVisibility`
/// (when the pill is shown at all).
///
/// Three variants:
/// * `.classic` — full-size pill (default).
/// * `.mini`    — compact pill whose recording controls appear on hover.
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

    var metrics: PillStyleMetrics {
        switch self {
        case .classic, .none:
            return .classic
        case .mini:
            return .mini
        }
    }
}

struct PillStyleMetrics: Equatable {
    let idleSize: CGSize
    let idleHoverSize: CGSize
    let holdToRecordSize: CGSize
    let recordingSize: CGSize
    let recordingHoverSize: CGSize
    let pausedSize: CGSize
    let transcribingSize: CGSize
    let doneSize: CGSize
    let downloadingSize: CGSize
    let loadingSize: CGSize
    let errorSize: CGSize
    let controlsOnHover: Bool
    let idleLogoSize: CGFloat
    let idleControlsSpacing: CGFloat
    let idleControlsInset: CGFloat
    let modeIconSize: CGFloat
    let recordLogoSize: CGFloat
    let recordingSpacing: CGFloat
    let controlDiameter: CGFloat
    let stopDiameter: CGFloat
    let recordingHorizontalInset: CGFloat
    let waveformRestWidth: CGFloat
    let waveformControlsWidth: CGFloat
    let pausedSpacing: CGFloat
    let pausedHorizontalInset: CGFloat
    let pausedFontSize: CGFloat
    let statusSpacing: CGFloat
    let statusHorizontalInset: CGFloat
    let statusFontSize: CGFloat

    static let classic = PillStyleMetrics(
        idleSize: CGSize(width: 80, height: 28),
        idleHoverSize: CGSize(width: 80, height: 28),
        holdToRecordSize: CGSize(width: 220, height: 36),
        recordingSize: CGSize(width: 220, height: 36),
        recordingHoverSize: CGSize(width: 220, height: 36),
        pausedSize: CGSize(width: 220, height: 36),
        transcribingSize: CGSize(width: 220, height: 36),
        doneSize: CGSize(width: 80, height: 28),
        downloadingSize: CGSize(width: 220, height: 36),
        loadingSize: CGSize(width: 220, height: 36),
        errorSize: CGSize(width: 220, height: 36),
        controlsOnHover: false,
        idleLogoSize: 14,
        idleControlsSpacing: 4,
        idleControlsInset: 3,
        modeIconSize: 10,
        recordLogoSize: 11,
        recordingSpacing: 8,
        controlDiameter: 22,
        stopDiameter: 20,
        recordingHorizontalInset: 8,
        waveformRestWidth: 132,
        waveformControlsWidth: 132,
        pausedSpacing: 12,
        pausedHorizontalInset: 15,
        pausedFontSize: 12,
        statusSpacing: 8,
        statusHorizontalInset: 12,
        statusFontSize: 12
    )

    static let mini = PillStyleMetrics(
        idleSize: CGSize(width: 40, height: 16),
        idleHoverSize: CGSize(width: 66, height: 30),
        holdToRecordSize: CGSize(width: 165, height: 27),
        recordingSize: CGSize(width: 110, height: 20),
        recordingHoverSize: CGSize(width: 170, height: 30),
        pausedSize: CGSize(width: 170, height: 30),
        transcribingSize: CGSize(width: 165, height: 27),
        doneSize: CGSize(width: 60, height: 21),
        downloadingSize: CGSize(width: 165, height: 27),
        loadingSize: CGSize(width: 165, height: 27),
        errorSize: CGSize(width: 165, height: 27),
        controlsOnHover: true,
        idleLogoSize: 10,
        idleControlsSpacing: 4,
        idleControlsInset: 3,
        modeIconSize: 10,
        recordLogoSize: 11,
        recordingSpacing: 6,
        controlDiameter: 24,
        stopDiameter: 22,
        recordingHorizontalInset: 4,
        waveformRestWidth: 90,
        waveformControlsWidth: 98,
        pausedSpacing: 6,
        pausedHorizontalInset: 7,
        pausedFontSize: 11,
        statusSpacing: 6,
        statusHorizontalInset: 9,
        statusFontSize: 10
    )
}
