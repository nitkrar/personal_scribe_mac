import SwiftUI

/// A reusable list-row surface showing a title, timestamp, and a
/// truncated preview of the transcript body text.
///
/// ## Scope
/// Consumed by `HistoryPanel` and `NotesSidebar` (both Phase 3). Depends
/// only on `PersonalScribeTheme` — no other component imports. This is the
/// Sprint 2 Lane B2 composite per `Component_Inventory.md` row 17 /
/// PLAN_PHASES.md Sprint 2.
///
/// ## Typography
/// * Title → `Typography.body` (13pt regular) with semibold weight.
/// * Preview → `Typography.caption` (11pt regular).
/// * Timestamp → `Typography.caption` (11pt regular), secondary text.
public struct TranscriptRow: View {
    public let title: String
    public let timestamp: Date
    public let preview: String
    public let isSelected: Bool

    /// Reference `now` used for relative-timestamp formatting. Injected
    /// so tests can reason about the output deterministically.
    private let referenceDate: Date

    @Environment(\.colorScheme) private var colorScheme

    public init(
        title: String,
        timestamp: Date,
        preview: String,
        isSelected: Bool = false,
        referenceDate: Date = Date()
    ) {
        self.title = title
        self.timestamp = timestamp
        self.preview = preview
        self.isSelected = isSelected
        self.referenceDate = referenceDate
    }

    // Exposed for tests.
    internal var displayTitle: String {
        Formatters.truncate(title, maxLength: Layout.titleMaxLength)
    }

    internal var displayPreview: String {
        Formatters.collapseWhitespace(preview)
    }

    internal var displayTimestamp: String {
        Formatters.relativeTimestamp(
            from: timestamp,
            to: referenceDate
        )
    }

    public var body: some View {
        let palette = PersonalScribeTheme.Palette.for(scheme: colorScheme)

        VStack(alignment: .leading, spacing: Layout.innerSpacing) {
            HStack(alignment: .firstTextBaseline, spacing: Layout.titleTimestampSpacing) {
                Text(displayTitle)
                    .font(PersonalScribeTheme.Typography.body.font.weight(.semibold))
                    .foregroundStyle(palette.primaryText)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 0)

                Text(displayTimestamp)
                    .font(PersonalScribeTheme.Typography.caption.font)
                    .foregroundStyle(palette.secondaryText)
                    .lineLimit(1)
            }

            if !displayPreview.isEmpty {
                Text(displayPreview)
                    .font(PersonalScribeTheme.Typography.caption.font)
                    .foregroundStyle(palette.secondaryText)
                    .lineLimit(Layout.previewLineLimit)
                    .truncationMode(.tail)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, PersonalScribeTheme.Spacing.rowPadding)
        .padding(.vertical, PersonalScribeTheme.Spacing.iconPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: PersonalScribeTheme.Radius.row, style: .continuous)
                .fill(isSelected ? palette.hoverState : palette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: PersonalScribeTheme.Radius.row, style: .continuous)
                .strokeBorder(
                    palette.brandChampagne.opacity(Layout.borderOpacity),
                    lineWidth: Layout.borderWidth
                )
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(displayTitle), \(displayTimestamp)")
        .accessibilityHint(displayPreview)
    }

    // MARK: - Layout constants

    internal enum Layout {
        static let titleMaxLength: Int = 60
        static let previewLineLimit: Int = 2
        static let innerSpacing: CGFloat = 4
        static let titleTimestampSpacing: CGFloat = 8
        static let borderWidth: CGFloat = 0.5
        static let borderOpacity: Double = 0.12
    }

    // MARK: - Pure formatting helpers (tested)

    /// Pure helpers exposed for TDD — no SwiftUI dependency.
    public enum Formatters {
        /// Collapse any run of whitespace / newlines into a single space.
        /// Keeps list preview lines tidy when the source text contains
        /// wrapping whitespace.
        public static func collapseWhitespace(_ input: String) -> String {
            let components = input
                .components(separatedBy: .whitespacesAndNewlines)
                .filter { !$0.isEmpty }
            return components.joined(separator: " ")
        }

        /// Truncate a string to `maxLength` characters, appending an
        /// ellipsis (`…`) if the input is longer. Keeps the truncated
        /// string's visible length ≤ `maxLength` including the ellipsis.
        public static func truncate(_ input: String, maxLength: Int) -> String {
            guard maxLength > 0 else { return "" }
            guard input.count > maxLength else { return input }
            let keep = max(maxLength - 1, 0)
            let prefix = String(input.prefix(keep))
            return prefix + "\u{2026}"
        }

        /// Produce a short human-readable relative timestamp.
        ///
        /// Buckets:
        /// * `< 60s`   → `"Just now"`
        /// * `< 60m`   → `"<n>m ago"`
        /// * `< 24h`   → `"<n>h ago"`
        /// * `< 7d`    → `"<n>d ago"`
        /// * `>= 7d`   → short calendar date (`"Mar 12"`), current year.
        /// * different year → `"Mar 12, 2023"`.
        /// * future dates (`timestamp > referenceDate`) → `"Just now"`.
        public static func relativeTimestamp(
            from timestamp: Date,
            to referenceDate: Date,
            calendar: Calendar = .autoupdatingCurrent,
            locale: Locale = .autoupdatingCurrent
        ) -> String {
            let delta = referenceDate.timeIntervalSince(timestamp)
            if delta < 60 {
                return "Just now"
            }
            let minutes = Int(delta / 60)
            if minutes < 60 {
                return "\(minutes)m ago"
            }
            let hours = Int(delta / 3600)
            if hours < 24 {
                return "\(hours)h ago"
            }
            let days = Int(delta / 86400)
            if days < 7 {
                return "\(days)d ago"
            }
            let formatter = DateFormatter()
            formatter.locale = locale
            formatter.calendar = calendar
            let sameYear = calendar.component(.year, from: timestamp)
                == calendar.component(.year, from: referenceDate)
            formatter.setLocalizedDateFormatFromTemplate(
                sameYear ? "MMMd" : "MMMdyyyy"
            )
            return formatter.string(from: timestamp)
        }
    }
}

#Preview("TranscriptRow — variants") {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    VStack(spacing: PersonalScribeTheme.Components.Preview.compactRowSpacing) {
        TranscriptRow(
            title: "Product sync notes",
            timestamp: now.addingTimeInterval(-30),
            preview: "We reviewed the roadmap and aligned on shipping the pill overlay first.",
            referenceDate: now
        )
        TranscriptRow(
            title: "Long title that easily exceeds the truncation threshold so we can see the ellipsis behaviour in the preview",
            timestamp: now.addingTimeInterval(-60 * 45),
            preview: "Short body.",
            referenceDate: now
        )
        TranscriptRow(
            title: "Selected row",
            timestamp: now.addingTimeInterval(-60 * 60 * 3),
            preview: "Selected state has a subtle hover background so it reads as active.",
            isSelected: true,
            referenceDate: now
        )
        TranscriptRow(
            title: "Yesterday",
            timestamp: now.addingTimeInterval(-60 * 60 * 30),
            preview: "",
            referenceDate: now
        )
    }
    .padding(PersonalScribeTheme.Components.Preview.canvasPadding)
    .background(PersonalScribeTheme.Palette.dark.appBackground)
    .preferredColorScheme(.dark)
}
