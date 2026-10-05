import PersonalScribeCore
import SwiftUI

@MainActor
struct HomeTab: View {
    @ObservedObject private var viewModel: HomeTabViewModel
    @ObservedObject private var metrics: MetricsSnapshotStore
    @ObservedObject private var checklist: HomeChecklistState
    private let referenceDate: Date

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.windowTint) private var windowTint

    init(viewModel: HomeTabViewModel, referenceDate: Date = Date()) {
        self.viewModel = viewModel
        self.metrics = viewModel.metrics
        self.checklist = viewModel.checklist
        self.referenceDate = referenceDate
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if viewModel.isCompletionBannerVisible {
                    completionBanner
                        .padding(.bottom, PersonalScribeTheme.Spacing.lg)
                }

                Text("Home")
                    .font(PersonalScribeTheme.Typography.largeTitle.font)
                    .foregroundStyle(palette.primaryTextBase)

                dictationCard
                    .padding(.top, PersonalScribeTheme.Spacing.xl)

                if checklist.isVisible {
                    checklistCard
                        .padding(.top, PersonalScribeTheme.Spacing.lg)
                }

                recentTranscriptions
                    .padding(.top, PersonalScribeTheme.Spacing.xl)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear {
            viewModel.refreshHotkey()
        }
    }

    private var completionBanner: some View {
        HStack(spacing: PersonalScribeTheme.Spacing.md) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(PersonalScribeTheme.Status.success)
            VStack(alignment: .leading, spacing: 2) {
                Text("You're set up")
                    .font(PersonalScribeTheme.Typography.body.font.weight(.semibold))
                Text("Use your shortcut in any app to dictate. Ninimma lives in the menu bar.")
                    .font(PersonalScribeTheme.Typography.caption.font)
                    .foregroundStyle(palette.secondaryText)
            }
            Spacer()
            Button { viewModel.dismissCompletionBanner() } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss setup complete")
        }
        .padding(PersonalScribeTheme.Spacing.md)
        .homeCard(
            background: cardSurface,
            border: PersonalScribeTheme.Status.success.opacity(0.45)
        )
    }

    private var dictationCard: some View {
        let palette = palette

        return VStack(alignment: .leading, spacing: PersonalScribeTheme.Spacing.lg) {
            HStack {
                Text("Your dictation")
                    .font(PersonalScribeTheme.Typography.sectionLabel.font)
                    .foregroundStyle(palette.secondaryText)
                    .textCase(.uppercase)

                Spacer()

                rangeMenu
            }

            HStack(spacing: 0) {
                metricCell(
                    label: "Words per minute avg",
                    value: formattedWPM,
                    suffix: "wpm",
                    leadingPadding: 0
                )
                metricDivider
                metricCell(label: "Words", value: formattedWords)
                metricDivider
                metricCell(label: "Recordings", value: formattedRecordings)
                metricDivider
                metricCell(
                    label: "Time saved",
                    value: Self.timeSavedText(minutes: metrics.rollups.minutesSaved)
                )
            }
        }
        .padding(PersonalScribeTheme.Spacing.lg)
        .homeCard(background: cardSurface, border: palette.brandChampagne.opacity(0.14))
    }

    private var checklistCard: some View {
        let palette = palette

        return VStack(spacing: 0) {
            HStack {
                Text("Get started")
                    .font(PersonalScribeTheme.Typography.body.font.weight(.semibold))
                    .foregroundStyle(palette.primaryTextBase)

                Spacer()

                Button {
                    checklist.dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(palette.secondaryText)
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss Get started")
            }
            .padding(.horizontal, PersonalScribeTheme.Spacing.lg)
            .padding(.vertical, 10)

            Divider()

            ForEach(checklist.pendingItems, id: \.self) { item in
                checklistRow(item)
                if item != checklist.pendingItems.last {
                    Divider()
                }
            }
        }
        .homeCard(background: cardSurface, border: palette.brandChampagne.opacity(0.14))
    }

    private func checklistRow(_ item: HomeChecklistItem) -> some View {
        let palette = palette

        return HStack(spacing: 0) {
            Button {
                checklist.complete(item)
            } label: {
                ZStack {
                    Circle()
                        .strokeBorder(palette.secondaryText, lineWidth: 1.5)
                        .frame(width: 18, height: 18)
                }
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Mark \(item.title) done")

            Button {
                viewModel.performChecklistAction(for: item)
            } label: {
                HStack(spacing: PersonalScribeTheme.Spacing.md) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title)
                            .font(
                                PersonalScribeTheme.Typography.body.font.weight(.semibold)
                            )
                            .foregroundStyle(palette.primaryTextBase)
                        Text(item.subtitle)
                            .font(PersonalScribeTheme.Typography.caption.font)
                            .foregroundStyle(palette.secondaryText)
                            .lineLimit(1)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(palette.secondaryText)
                }
                .padding(.leading, PersonalScribeTheme.Spacing.sm)
                .padding(.trailing, PersonalScribeTheme.Spacing.lg)
                .padding(.vertical, PersonalScribeTheme.Spacing.sm)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(item.title)
            .accessibilityHint(item.navigationHint)
        }
        .padding(.leading, PersonalScribeTheme.Spacing.sm)
    }

    private var recentTranscriptions: some View {
        VStack(alignment: .leading, spacing: PersonalScribeTheme.Spacing.md) {
            Text("Recent transcriptions")
                .font(PersonalScribeTheme.Typography.sectionLabel.font)
                .foregroundStyle(palette.secondaryText)
                .textCase(.uppercase)

            if metrics.recentTranscriptions.isEmpty {
                emptyStateView
            } else {
                VStack(spacing: PersonalScribeTheme.Spacing.sm) {
                    ForEach(metrics.recentTranscriptions, id: \.id) { entry in
                        recentTranscriptionRow(entry)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: PersonalScribeTheme.Spacing.lg) {
            PersonalScribeLogoView(color: palette.brandChampagne)
                .frame(width: 64, height: 64)

            VStack(spacing: PersonalScribeTheme.Spacing.sm) {
                Text("No transcriptions yet")
                    .font(PersonalScribeTheme.Typography.body.font)
                    .foregroundStyle(palette.primaryTextBase)
                HStack(spacing: PersonalScribeTheme.Spacing.xs) {
                    Text("Press")
                    hotkeyKeycap
                    Text("to start recording")
                }
                    .font(PersonalScribeTheme.Typography.caption.font)
                    .foregroundStyle(palette.secondaryText)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, PersonalScribeTheme.Spacing.xl)
    }

    private var hotkeyKeycap: some View {
        Text(viewModel.emptyStateHotkeyHint)
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .foregroundStyle(palette.primaryTextBase)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(palette.secondaryText.opacity(0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(palette.secondaryText.opacity(0.3), lineWidth: 0.5)
            )
    }

    private func recentTranscriptionRow(_ entry: TranscriptEntry) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: PersonalScribeTheme.Spacing.md) {
                Text(Self.title(for: entry))
                    .font(PersonalScribeTheme.Typography.body.font.weight(.semibold))
                    .foregroundStyle(palette.primaryTextBase)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .layoutPriority(1)

                Spacer(minLength: PersonalScribeTheme.Spacing.md)

                Text(
                    TranscriptRow.Formatters.relativeTimestamp(
                        from: entry.timestamp,
                        to: referenceDate
                    )
                )
                .font(PersonalScribeTheme.Typography.caption.font)
                .foregroundStyle(palette.secondaryText)
                .lineLimit(1)
                .fixedSize()
            }

            Text(TranscriptRow.Formatters.collapseWhitespace(entry.text))
                .font(PersonalScribeTheme.Typography.caption.font)
                .foregroundStyle(palette.secondaryText)
                .lineLimit(1)
        }
        .padding(.horizontal, PersonalScribeTheme.Spacing.rowPadding)
        .padding(.vertical, 9)
        .homeCard(background: cardSurface, border: palette.brandChampagne.opacity(0.14))
    }

    private func metricCell(
        label: String,
        value: String,
        suffix: String? = nil,
        leadingPadding: CGFloat = PersonalScribeTheme.Spacing.lg
    ) -> some View {
        VStack(alignment: .leading, spacing: PersonalScribeTheme.Spacing.sm) {
            Text(label)
                .font(PersonalScribeTheme.Typography.body.font)
                .foregroundStyle(palette.secondaryText)
                .lineLimit(1)

            HStack(alignment: .firstTextBaseline, spacing: PersonalScribeTheme.Spacing.xs) {
                Text(value)
                    .font(PersonalScribeTheme.Typography.largeTitle.font)
                    .foregroundStyle(palette.primaryTextBase)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if let suffix {
                    Text(suffix)
                        .font(PersonalScribeTheme.Typography.body.font.weight(.semibold))
                        .foregroundStyle(palette.secondaryText)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, leadingPadding)
        .padding(.trailing, PersonalScribeTheme.Spacing.lg)
    }

    private var metricDivider: some View {
        Divider().frame(height: 50)
    }

    private func selectRange(_ range: MetricsRange) {
        Task { @MainActor in
            await metrics.selectRange(range)
        }
    }

    private var rangeMenu: some View {
        rangeMenuLabel
            .overlay(
                Capsule()
                    .strokeBorder(palette.secondaryText.opacity(0.35), lineWidth: 0.5)
            )
            .overlay {
                Menu {
                    ForEach(MetricsRange.allCases) { range in
                        Button(range.title) {
                            selectRange(range)
                        }
                    }
                } label: {
                    Color.clear
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Capsule())
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
            }
            .fixedSize()
    }

    private var rangeMenuLabel: some View {
        HStack(spacing: 6) {
            Text(metrics.selectedRange.title)
            Image(systemName: "chevron.down")
                .font(.system(size: 9, weight: .semibold))
        }
        .font(PersonalScribeTheme.Typography.body.font)
        .foregroundStyle(palette.primaryTextBase)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .contentShape(Capsule())
    }

    private var formattedWPM: String {
        Self.wpmFormatter.string(from: NSNumber(value: metrics.rollups.averageWPM))
            ?? String(format: "%.1f", metrics.rollups.averageWPM)
    }

    private var formattedWords: String {
        Self.integerFormatter.string(from: NSNumber(value: metrics.rollups.words))
            ?? "\(metrics.rollups.words)"
    }

    private var formattedRecordings: String {
        Self.integerFormatter.string(from: NSNumber(value: metrics.rollups.recordings))
            ?? "\(metrics.rollups.recordings)"
    }

    private var palette: PersonalScribeTheme.Palette {
        PersonalScribeTheme.Palette.for(scheme: colorScheme)
    }

    private var cardSurface: Color {
        if colorScheme == .dark {
            return palette.elevatedSurface
        }
        return windowTint?.cardBackground ?? palette.surface
    }

    static func timeSavedText(minutes: Double) -> String {
        let totalMinutes = max(0, Int(minutes.rounded()))
        let hours = totalMinutes / 60
        let remainingMinutes = totalMinutes % 60
        guard hours > 0 else {
            return "\(remainingMinutes)m"
        }
        return "\(hours)h \(remainingMinutes)m"
    }

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

    private static let integerFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        formatter.usesGroupingSeparator = true
        return formatter
    }()

    private static let wpmFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 1
        return formatter
    }()
}

private extension View {
    func homeCard(background: Color, border: Color) -> some View {
        self.background(
            RoundedRectangle(
                cornerRadius: PersonalScribeTheme.Radius.md,
                style: .continuous
            )
            .fill(background)
        )
        .clipShape(
            RoundedRectangle(
                cornerRadius: PersonalScribeTheme.Radius.md,
                style: .continuous
            )
        )
        .overlay(
            RoundedRectangle(
                cornerRadius: PersonalScribeTheme.Radius.md,
                style: .continuous
            )
            .strokeBorder(border, lineWidth: 0.5)
        )
    }
}
