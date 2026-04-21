import PersonalScribeCore
import SwiftUI

/// Home tab for the unified NavigationSplitView window (M3.5).
///
/// Layout: header "Home" + a 4-cell stat card grid (Words this week,
/// Recordings, Minutes saved, WPM avg) + a "Recent" section showing the
/// 3 most-recent transcripts via the shared `TranscriptRow` composite.
///
/// Data source: `HomeTabViewModel`, which consumes the existing L8
/// `MetricsReading.loadSnapshot(window:, recentLimit:)`. Reactive
/// refresh is driven by `MetricsNotification.transcriptCommit`.
///
/// Reference: `plans/App UI design/Claude_Final_Bundle_Prompt.md` §3A.
@MainActor
struct HomeTab: View {
    @ObservedObject private var viewModel: HomeTabViewModel

    @Environment(\.colorScheme) private var colorScheme

    init(viewModel: HomeTabViewModel) {
        self.viewModel = viewModel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: PersonalScribeTheme.Spacing.xl) {
            Text("Home")
                .font(PersonalScribeTheme.Typography.largeTitle.font)

            statCardGrid

            VStack(alignment: .leading, spacing: PersonalScribeTheme.Spacing.md) {
                Text("Recent transcriptions")
                    .font(PersonalScribeTheme.Typography.sectionLabel.font)
                    .textCase(.uppercase)

                if viewModel.recent.isEmpty {
                    emptyStateView
                } else {
                    ForEach(viewModel.recent.prefix(HomeTabViewModel.recentLimit), id: \.id) { entry in
                        TranscriptRow(
                            title: Self.title(for: entry),
                            timestamp: entry.timestamp,
                            preview: entry.text
                        )
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task {
            await viewModel.load()
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: MetricsNotification.transcriptCommit
            )
        ) { _ in
            Task { @MainActor in
                await viewModel.refresh()
            }
        }
    }

    // MARK: - Empty state (mockup-gaps B.1)

    /// Vertically-stacked empty-state view shown when
    /// `viewModel.recent.isEmpty`. Matches `plans/App UI design/screen_home.png`:
    /// a champagne feather + "No transcriptions yet" primary line and a
    /// secondary "Press <hotkey> to start recording" hint. The hotkey
    /// string comes from `viewModel.emptyStateHotkeyHint` — it MUST NOT
    /// be hardcoded so it reflects the user's actual binding.
    private var emptyStateView: some View {
        let palette = PersonalScribeTheme.Palette.for(scheme: colorScheme)
        // Logo size is inline (no dedicated theme constant yet) —
        // 64pt reads at the same visual weight as the mockup feather
        // without over-dominating the column.
        let logoSize: CGFloat = 64

        return VStack(spacing: PersonalScribeTheme.Spacing.lg) {
            PersonalScribeLogoView(color: palette.brandChampagne)
                .frame(width: logoSize, height: logoSize)

            VStack(spacing: PersonalScribeTheme.Spacing.sm) {
                Text("No transcriptions yet")
                    .font(PersonalScribeTheme.Typography.body.font)
                    .foregroundStyle(palette.primaryText)

                Text("Press \(viewModel.emptyStateHotkeyHint) to start recording")
                    .font(PersonalScribeTheme.Typography.caption.font)
                    .foregroundStyle(palette.secondaryText)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, PersonalScribeTheme.Spacing.xl)
    }

    // MARK: - Stat cards

    private var statCardGrid: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 150), spacing: PersonalScribeTheme.Spacing.md)],
            alignment: .leading,
            spacing: PersonalScribeTheme.Spacing.md
        ) {
            StatCard(
                label: "Words this week",
                value: Self.integerFormatter.string(
                    from: NSNumber(value: viewModel.rollups.wordsThisWeek)
                ) ?? "\(viewModel.rollups.wordsThisWeek)"
            )
            StatCard(
                label: "Recordings",
                value: Self.integerFormatter.string(
                    from: NSNumber(value: viewModel.rollups.recordingsThisWeek)
                ) ?? "\(viewModel.rollups.recordingsThisWeek)"
            )
            StatCard(
                label: "Minutes saved",
                value: Self.minutesFormatter.string(
                    from: NSNumber(value: viewModel.rollups.minutesSavedThisWeek.rounded())
                ) ?? "\(Int(viewModel.rollups.minutesSavedThisWeek.rounded()))"
            )
            StatCard(
                label: "WPM avg",
                value: Self.wpmFormatter.string(
                    from: NSNumber(value: viewModel.rollups.averageWPMThisWeek)
                ) ?? String(format: "%.1f", viewModel.rollups.averageWPMThisWeek)
            )
        }
    }

    // MARK: - Derivation

    /// Title for a transcript row. Matches the legacy History/Notes
    /// convention: first non-empty whitespace-trimmed line, truncated
    /// by `TranscriptRow` itself. Falls back to a short date stamp
    /// when the text is empty.
    static func title(for entry: TranscriptEntry) -> String {
        let firstLine = entry.text
            .split(whereSeparator: \.isNewline)
            .first
            .map(String.init)?
            .trimmingCharacters(in: .whitespaces)
            ?? ""
        if !firstLine.isEmpty {
            return firstLine
        }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: entry.timestamp)
    }

    // MARK: - Formatters

    private static let integerFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        formatter.usesGroupingSeparator = true
        return formatter
    }()

    private static let minutesFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        formatter.usesGroupingSeparator = true
        return formatter
    }()

    private static let wpmFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 1
        formatter.maximumFractionDigits = 1
        return formatter
    }()
}

// MARK: - StatCard

/// Compact stat card: caption label stacked above a large value.
/// Card surface uses the environment `WindowTint` when provided,
/// otherwise falls back to the theme elevated-surface colour.
@MainActor
private struct StatCard: View {
    let label: String
    let value: String

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.windowTint) private var windowTint

    var body: some View {
        let palette = PersonalScribeTheme.Palette.for(scheme: colorScheme)
        let background = windowTint?.cardBackground ?? palette.elevatedSurface

        VStack(alignment: .leading, spacing: PersonalScribeTheme.Spacing.xs) {
            Text(label)
                .font(PersonalScribeTheme.Typography.caption.font)
                .foregroundStyle(palette.secondaryText)
                .lineLimit(1)
                .truncationMode(.tail)

            Text(value)
                .font(PersonalScribeTheme.Typography.largeTitle.font)
                .foregroundStyle(palette.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .padding(PersonalScribeTheme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: PersonalScribeTheme.Radius.md, style: .continuous)
                .fill(background)
        )
        .overlay(
            RoundedRectangle(cornerRadius: PersonalScribeTheme.Radius.md, style: .continuous)
                .strokeBorder(
                    palette.brandChampagne.opacity(0.12),
                    lineWidth: 0.5
                )
        )
    }
}

