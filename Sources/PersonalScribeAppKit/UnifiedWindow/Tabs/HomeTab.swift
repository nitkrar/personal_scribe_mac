import PersonalScribeCore
import SwiftUI

@MainActor
struct HomeTab: View {
    @ObservedObject private var viewModel: HomeTabViewModel
    @ObservedObject private var metrics: MetricsSnapshotStore
    @ObservedObject private var checklist: HomeChecklistState

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.windowTint) private var windowTint

    init(viewModel: HomeTabViewModel) {
        self.viewModel = viewModel
        self.metrics = viewModel.metrics
        self.checklist = viewModel.checklist
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PersonalScribeTheme.Spacing.xl) {
                Text("Home")
                    .font(PersonalScribeTheme.Typography.largeTitle.font)

                dictationCard

                if checklist.isVisible {
                    checklistCard
                }

                recentTranscriptions
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear {
            viewModel.refreshHotkey()
            viewModel.refreshChecklist()
        }
        .onChange(of: metrics.recentTranscriptions.count) {
            viewModel.refreshChecklist()
        }
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

                Picker("Metrics range", selection: rangeBinding) {
                    ForEach(MetricsRange.allCases) { range in
                        Text(range.title).tag(range)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
            }

            HStack(spacing: 0) {
                metricCell(label: "Words per minute avg", value: formattedWPM, suffix: "wpm")
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
        .homeCard(background: cardBackground, border: palette.brandChampagne.opacity(0.14))
    }

    private var checklistCard: some View {
        let palette = palette

        return VStack(spacing: 0) {
            HStack(spacing: PersonalScribeTheme.Spacing.md) {
                Text("Get started")
                    .font(PersonalScribeTheme.Typography.title.font)
                    .foregroundStyle(palette.primaryText)

                Text("\(checklist.completedCount) of \(HomeChecklistItem.allCases.count)")
                    .font(PersonalScribeTheme.Typography.body.font)
                    .foregroundStyle(palette.secondaryText)

                ProgressView(
                    value: Double(checklist.completedCount),
                    total: Double(HomeChecklistItem.allCases.count)
                )
                .progressViewStyle(.linear)
                .frame(width: 96)

                Spacer()

                if checklist.isComplete {
                    Button("Dismiss") {
                        checklist.dismiss()
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(palette.secondaryText)
                }
            }
            .padding(PersonalScribeTheme.Spacing.lg)

            Divider()

            checklistRow(
                item: .startRecording,
                title: "Start recording",
                subtitle: "Press \(viewModel.emptyStateHotkeyHint) in any app, speak, press again to paste"
            )
            Divider()
            checklistRow(
                item: .customizeShortcut,
                title: "Customize your shortcut",
                subtitle: "Pick a key combo that suits you · Settings → Shortcuts"
            )
            Divider()
            checklistRow(
                item: .createMode,
                title: "Create a mode",
                subtitle: "Different formatting per app, e.g. email vs. code · Modes"
            )
        }
        .homeCard(background: cardBackground, border: palette.brandChampagne.opacity(0.14))
    }

    private func checklistRow(
        item: HomeChecklistItem,
        title: String,
        subtitle: String
    ) -> some View {
        let palette = palette
        let isComplete = checklist.completedItems.contains(item)

        return Button {
            viewModel.performChecklistAction(for: item)
        } label: {
            HStack(spacing: PersonalScribeTheme.Spacing.md) {
                ZStack {
                    Circle()
                        .fill(isComplete ? palette.statusReady : .clear)
                    Circle()
                        .strokeBorder(
                            isComplete ? palette.statusReady : palette.secondaryText,
                            lineWidth: 1.5
                        )
                    if isComplete {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Color.white)
                    }
                }
                .frame(width: 20, height: 20)

                VStack(alignment: .leading, spacing: PersonalScribeTheme.Spacing.xs) {
                    Text(title)
                        .font(PersonalScribeTheme.Typography.body.font.weight(.semibold))
                        .strikethrough(isComplete)
                        .foregroundStyle(
                            isComplete ? palette.secondaryText : palette.primaryText
                        )
                    Text(subtitle)
                        .font(PersonalScribeTheme.Typography.caption.font)
                        .foregroundStyle(palette.secondaryText)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(palette.secondaryText)
            }
            .contentShape(Rectangle())
            .padding(.horizontal, PersonalScribeTheme.Spacing.lg)
            .padding(.vertical, PersonalScribeTheme.Spacing.md)
        }
        .buttonStyle(.plain)
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
                ForEach(metrics.recentTranscriptions, id: \.id) { entry in
                    TranscriptRow(
                        title: Self.title(for: entry),
                        timestamp: entry.timestamp,
                        preview: entry.text
                    )
                }
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
                    .foregroundStyle(palette.primaryText)
                Text("Press \(viewModel.emptyStateHotkeyHint) to start recording")
                    .font(PersonalScribeTheme.Typography.caption.font)
                    .foregroundStyle(palette.secondaryText)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, PersonalScribeTheme.Spacing.xl)
    }

    private func metricCell(label: String, value: String, suffix: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: PersonalScribeTheme.Spacing.sm) {
            Text(label)
                .font(PersonalScribeTheme.Typography.body.font)
                .foregroundStyle(palette.secondaryText)
                .lineLimit(1)

            HStack(alignment: .firstTextBaseline, spacing: PersonalScribeTheme.Spacing.xs) {
                Text(value)
                    .font(PersonalScribeTheme.Typography.largeTitle.font)
                    .foregroundStyle(palette.primaryText)
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
        .padding(.horizontal, PersonalScribeTheme.Spacing.lg)
    }

    private var metricDivider: some View {
        Divider().frame(height: 50)
    }

    private var rangeBinding: Binding<MetricsRange> {
        Binding(
            get: { metrics.selectedRange },
            set: { range in
                Task { @MainActor in
                    await metrics.selectRange(range)
                }
            }
        )
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
        PersonalScribeTheme.Palette.for(scheme: colorScheme, tint: windowTint)
    }

    private var cardBackground: Color {
        windowTint?.cardBackground ?? palette.elevatedSurface
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
