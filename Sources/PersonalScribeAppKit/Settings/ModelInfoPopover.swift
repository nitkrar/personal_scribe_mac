import SwiftUI
import PersonalScribeCore

/// Info popover attached to the ⓘ icon next to each voice-model's
/// display name in `AIModelsTab`. Layout (top → bottom):
///
///   1. Header — display name + short description
///   2. Hero trio — Speed / Accuracy / Size as three equal-width cards
///   3. Divider
///   4. Human-friendly meta rows — Made by / Works with / Good for /
///      Model type / License  (only rows with non-nil values)
///   5. Divider
///   6. Technical detail rows — Architecture / Repository / Revision /
///      Parameters (when declared)
///
/// Content derives entirely from `ModelInfoPopoverPresenter` so all
/// label / ranking / formatting logic stays XCTest-able.
///
/// Ticket #007 (redesigned in #031).
@MainActor
struct ModelInfoPopover: View {
    let presenter: ModelInfoPopoverPresenter

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 12)

            heroTrio
                .padding(.horizontal, 16)
                .padding(.bottom, 12)

            Divider()
                .padding(.horizontal, 8)

            if !presenter.humanFriendlyRows.isEmpty {
                metaSection
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .padding(.bottom, 10)

                Divider()
                    .padding(.horizontal, 8)
            }

            detailSection
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 16)
        }
        .frame(width: 320)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(presenter.title)
                .font(PersonalScribeTheme.Typography.headline.font)

            if !presenter.subtitle.isEmpty {
                Text(presenter.subtitle)
                    .font(PersonalScribeTheme.Typography.caption.font)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Hero trio (Speed / Accuracy / Size)

    private var heroTrio: some View {
        HStack(spacing: 8) {
            if let speedRow = presenter.speedRow {
                heroRatingCard(
                    title: "Speed",
                    filled: speedRow.filledSegments,
                    total: speedRow.totalSegments,
                    label: speedRow.label,
                    barColor: PersonalScribeTheme.color(hex: "C9A96E")  // Clay
                )
            }

            if let accuracyRow = presenter.accuracyRow {
                heroRatingCard(
                    title: "Accuracy",
                    filled: accuracyRow.filledSegments,
                    total: accuracyRow.totalSegments,
                    label: accuracyRow.label,
                    barColor: PersonalScribeTheme.color(hex: "1B4F8A")  // Lapis
                )
            }

            heroSizeCard
        }
    }

    /// Card showing a segmented rating bar + label.
    private func heroRatingCard(
        title: String,
        filled: Int,
        total: Int,
        label: String,
        barColor: Color
    ) -> some View {
        VStack(spacing: 6) {
            Text(title)
                .font(PersonalScribeTheme.Typography.caption.font)
                .foregroundStyle(.secondary)

            ratingBar(filled: filled, total: total, color: barColor)
                .frame(height: 8)

            Text(label)
                .font(PersonalScribeTheme.Typography.caption.font.weight(.medium))
                .foregroundStyle(barColor)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
        )
    }

    /// Card showing the on-disk size as a number.
    private var heroSizeCard: some View {
        VStack(spacing: 6) {
            Text("Size")
                .font(PersonalScribeTheme.Typography.caption.font)
                .foregroundStyle(.secondary)

            Text(presenter.sizeValue)
                .font(PersonalScribeTheme.Typography.body.font.weight(.semibold))
                .foregroundStyle(.primary)
                .frame(height: 8, alignment: .center)
                .fixedSize()

            Text("on disk")
                .font(PersonalScribeTheme.Typography.caption.font)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
        )
    }

    /// Segmented bar with a given accent colour.
    /// Filled segments use the accent; unfilled use a muted opacity.
    private func ratingBar(filled: Int, total: Int, color: Color) -> some View {
        HStack(spacing: 3) {
            ForEach(0..<total, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(index < filled ? color : color.opacity(0.18))
                    .frame(height: 8)
            }
        }
        .padding(.horizontal, 8)
    }

    // MARK: - Human-friendly meta section

    private var metaSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(presenter.humanFriendlyRows, id: \.title) { row in
                infoRow(title: row.title, value: row.value, monospaced: row.monospaced)
            }
        }
    }

    // MARK: - Technical detail section

    private var detailSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(presenter.detailRows, id: \.title) { row in
                infoRow(title: row.title, value: row.value, monospaced: row.monospaced)
            }
        }
    }

    // MARK: - Shared row layout

    private func infoRow(title: String, value: String, monospaced: Bool) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(title)
                .font(PersonalScribeTheme.Typography.caption.font)
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .leading)

            Text(value)
                .font(
                    monospaced
                        ? .system(
                            size: PersonalScribeTheme.Typography.caption.pointSize,
                            design: .monospaced
                          )
                        : PersonalScribeTheme.Typography.caption.font
                )
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(2)
                .truncationMode(.middle)
        }
    }
}
