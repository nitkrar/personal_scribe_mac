import SwiftUI

/// A small rounded chip for metadata tags (e.g. "meeting", "idea").
///
/// Consumed by `NotesSidebar` and `NotesEditor` (Phase 3). This is a
/// Sprint 1 foundation per `Component_Inventory.md` row 4, NOT a Sprint
/// 2 re-build — see PLAN_PHASES.md line 323 for the bundle v3
/// inconsistency note.
public struct TagChip: View {
    public enum Variant: Hashable, Sendable {
        /// Subtle background, primary-text label. Default.
        case neutral
        /// Champagne-tinted background signalling an active filter or
        /// mode tag.
        case accent

        func foregroundColor(for palette: PersonalScribeTheme.Palette) -> Color {
            switch self {
            case .neutral: return palette.primaryText
            case .accent: return palette.brandChampagne
            }
        }

        func backgroundColor(for palette: PersonalScribeTheme.Palette) -> Color {
            switch self {
            case .neutral: return palette.elevatedSurface
            case .accent:
                return palette.brandChampagne.opacity(
                    PersonalScribeTheme.Components.TagChip.accentFillOpacity
                )
            }
        }

        func borderColor(for palette: PersonalScribeTheme.Palette) -> Color {
            switch self {
            case .neutral:
                return palette.brandChampagne.opacity(
                    PersonalScribeTheme.Components.TagChip.neutralBorderOpacity
                )
            case .accent:
                return palette.brandChampagne.opacity(
                    PersonalScribeTheme.Components.TagChip.accentBorderOpacity
                )
            }
        }
    }

    public let text: String
    public let variant: Variant

    @Environment(\.colorScheme) private var colorScheme

    public init(text: String, variant: Variant = .neutral) {
        self.text = text
        self.variant = variant
    }

    public var body: some View {
        let palette = PersonalScribeTheme.Palette.for(scheme: colorScheme)

        Text(text)
            .font(PersonalScribeTheme.Typography.caption.font)
            .foregroundStyle(variant.foregroundColor(for: palette))
            .padding(.horizontal, PersonalScribeTheme.Components.TagChip.horizontalPadding)
            .padding(.vertical, PersonalScribeTheme.Components.TagChip.verticalPadding)
            .background(
                RoundedRectangle(
                    cornerRadius: PersonalScribeTheme.Components.TagChip.cornerRadius,
                    style: .continuous
                )
                .fill(variant.backgroundColor(for: palette))
            )
            .overlay(
                RoundedRectangle(
                    cornerRadius: PersonalScribeTheme.Components.TagChip.cornerRadius,
                    style: .continuous
                )
                .strokeBorder(
                    variant.borderColor(for: palette),
                    lineWidth: PersonalScribeTheme.Components.TagChip.borderWidth
                )
            )
            .accessibilityElement()
            .accessibilityLabel("Tag \(text)")
    }
}

#Preview("TagChip — variants") {
    HStack(spacing: PersonalScribeTheme.Components.Preview.compactRowSpacing) {
        TagChip(text: "meeting")
        TagChip(text: "idea", variant: .accent)
        TagChip(text: "followup")
    }
    .padding(PersonalScribeTheme.Components.Preview.canvasPadding)
    .background(PersonalScribeTheme.Palette.dark.appBackground)
    .preferredColorScheme(.dark)
}
