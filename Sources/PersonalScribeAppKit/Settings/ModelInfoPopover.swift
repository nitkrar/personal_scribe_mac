import SwiftUI
import PersonalScribeCore

/// Info popover attached to the ⓘ icon next to each voice-model's
/// display name in `AIModelsTab`. Shows:
///   - Header: display name + short description
///   - Ratings: Speed and Accuracy as N-of-3 segment bars with labels
///   - Size: human-readable disk footprint
///   - Details: Architecture, Repository, Revision (monospaced),
///     Parameters (when declared)
///
/// Content derives entirely from `ModelInfoPopoverPresenter` so the
/// label / ranking / formatting logic stays XCTest-able. This view
/// is pure chrome around those computed values.
///
/// Ticket #007.
@MainActor
struct ModelInfoPopover: View {
    let presenter: ModelInfoPopoverPresenter

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            ratingsAndSize
            Divider()
            detailRowsView
        }
        .padding(16)
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

    // MARK: - Ratings + size

    private var ratingsAndSize: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let speedRow = presenter.speedRow {
                ratingRowView(speedRow)
            }
            if let accuracyRow = presenter.accuracyRow {
                ratingRowView(accuracyRow)
            }
            metricRow(title: "Size", value: presenter.sizeValue, monospaced: false)
        }
    }

    private func ratingRowView(
        _ row: ModelInfoPopoverPresenter.RatingRow
    ) -> some View {
        HStack(spacing: 8) {
            Text(row.title)
                .font(PersonalScribeTheme.Typography.caption.font)
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .leading)

            ratingBar(filled: row.filledSegments, total: row.totalSegments)
                .frame(width: 48)

            Text(row.label)
                .font(PersonalScribeTheme.Typography.caption.font.weight(.medium))

            Spacer(minLength: 0)
        }
    }

    /// Segmented bar: `filled` of `total` rounded-rectangle cells,
    /// filled with the champagne accent; unfilled cells use a muted
    /// surface tone so the empty state is visible against the popover
    /// background.
    private func ratingBar(filled: Int, total: Int) -> some View {
        let palette = PersonalScribeTheme.Palette.for(scheme: colorScheme)
        return HStack(spacing: 3) {
            ForEach(0..<total, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(
                        index < filled
                            ? palette.brandChampagne
                            : palette.brandChampagne.opacity(0.18)
                    )
                    .frame(height: 8)
            }
        }
    }

    // MARK: - Detail rows

    private var detailRowsView: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(presenter.detailRows, id: \.title) { row in
                metricRow(title: row.title, value: row.value, monospaced: row.monospaced)
            }
        }
    }

    private func metricRow(
        title: String,
        value: String,
        monospaced: Bool
    ) -> some View {
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
