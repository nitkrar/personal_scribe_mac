import SwiftUI

/// A compact audio-player surface showing a duration label and a static
/// waveform pose.
///
/// ## Scope
/// Consumed by the Notes Context Panel (Phase 3). Depends on
/// `WaveformView` + `SeshatTheme`. See `Component_Inventory.md` row 19
/// / PLAN_PHASES.md Sprint 2.
///
/// The waveform here is **static** — `WaveformView.isActive` is always
/// `false` so there is no `TimelineView` tick, matching the idle-pill
/// no-CPU decision. The displayed shape reflects the supplied
/// `levelPose` (0…1), which is clamped defensively at the view layer.
public struct AudioPlayerThumbnail: View {
    public let durationSeconds: TimeInterval
    public let levelPose: Double

    @Environment(\.colorScheme) private var colorScheme

    public init(
        durationSeconds: TimeInterval,
        levelPose: Double = 0.35
    ) {
        self.durationSeconds = durationSeconds
        self.levelPose = levelPose
    }

    // Exposed for tests.
    internal var durationLabel: String {
        Formatters.formatDuration(durationSeconds)
    }

    internal var clampedLevel: Double {
        Formatters.clampLevel(levelPose)
    }

    public var body: some View {
        let palette = SeshatTheme.Palette.for(scheme: colorScheme)

        let level = clampedLevel
        HStack(alignment: .center, spacing: Layout.itemSpacing) {
            // Static waveform pose — isActive is `.constant(false)` so no
            // TimelineView tick is created, matching the idle-pill
            // no-CPU decision (PLAN_PHASES.md line 351).
            WaveformView(
                audioLevel: .constant(level),
                isActive: .constant(false),
                barCount: Layout.waveformBarCount
            )
            .frame(height: Layout.waveformHeight)
            .allowsHitTesting(false)

            Text(durationLabel)
                .font(SeshatTheme.Typography.caption.font.monospacedDigit())
                .foregroundStyle(palette.secondaryText)
                .lineLimit(1)
        }
        .padding(.horizontal, SeshatTheme.Spacing.rowPadding)
        .padding(.vertical, SeshatTheme.Spacing.iconPadding)
        .background(
            RoundedRectangle(cornerRadius: SeshatTheme.Radius.row, style: .continuous)
                .fill(palette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: SeshatTheme.Radius.row, style: .continuous)
                .strokeBorder(
                    palette.brandChampagne.opacity(Layout.borderOpacity),
                    lineWidth: Layout.borderWidth
                )
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Audio clip, \(durationLabel)")
    }

    // MARK: - Layout constants

    internal enum Layout {
        static let itemSpacing: CGFloat = 8
        static let waveformHeight: CGFloat = 20
        static let waveformBarCount: Int = 16
        static let borderWidth: CGFloat = 0.5
        static let borderOpacity: Double = 0.12
    }

    // MARK: - Pure formatting helpers (tested)

    /// Pure helpers exposed for TDD — no SwiftUI dependency.
    public enum Formatters {
        /// Clamp a raw level value to `[0, 1]`. Also maps NaN / infinity
        /// to 0 so a malformed input never propagates into the waveform.
        public static func clampLevel(_ raw: Double) -> Double {
            guard raw.isFinite else { return 0 }
            return min(1.0, max(0.0, raw))
        }

        /// Format a non-negative duration in seconds as `mm:ss` for
        /// durations under an hour, or `h:mm:ss` otherwise. Negative
        /// values are treated as zero. NaN / infinity → `"0:00"`.
        public static func formatDuration(_ seconds: TimeInterval) -> String {
            guard seconds.isFinite else { return "0:00" }
            let clamped = max(0, seconds)
            let total = Int(clamped.rounded())
            let hours = total / 3600
            let minutes = (total % 3600) / 60
            let secs = total % 60
            if hours > 0 {
                return String(format: "%d:%02d:%02d", hours, minutes, secs)
            }
            return String(format: "%d:%02d", minutes, secs)
        }
    }
}

#Preview("AudioPlayerThumbnail — variants") {
    VStack(spacing: SeshatTheme.Components.Preview.stackSpacing) {
        AudioPlayerThumbnail(durationSeconds: 12, levelPose: 0.2)
        AudioPlayerThumbnail(durationSeconds: 75, levelPose: 0.5)
        AudioPlayerThumbnail(durationSeconds: 3_725, levelPose: 0.75)
    }
    .padding(SeshatTheme.Components.Preview.canvasPadding)
    .background(SeshatTheme.Palette.dark.appBackground)
    .preferredColorScheme(.dark)
}
