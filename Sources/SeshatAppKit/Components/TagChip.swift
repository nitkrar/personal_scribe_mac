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
    }

    public let text: String
    public let variant: Variant

    @Environment(\.colorScheme) private var colorScheme

    public init(text: String, variant: Variant = .neutral) {
        self.text = text
        self.variant = variant
    }

    public var body: some View {
        let palette = SeshatTheme.Palette.for(scheme: colorScheme)

        Text(text)
            .font(SeshatTheme.Typography.caption.font)
            .foregroundStyle(foreground(palette: palette))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: SeshatTheme.Radius.row - 2, style: .continuous)
                    .fill(background(palette: palette))
            )
            .overlay(
                RoundedRectangle(cornerRadius: SeshatTheme.Radius.row - 2, style: .continuous)
                    .strokeBorder(border(palette: palette), lineWidth: 0.5)
            )
            .accessibilityElement()
            .accessibilityLabel("Tag \(text)")
    }

    private func foreground(palette: SeshatTheme.Palette) -> Color {
        switch variant {
        case .neutral: return palette.primaryText
        case .accent: return palette.brandChampagne
        }
    }

    private func background(palette: SeshatTheme.Palette) -> Color {
        switch variant {
        case .neutral: return palette.elevatedSurface
        case .accent: return palette.brandChampagne.opacity(0.18)
        }
    }

    private func border(palette: SeshatTheme.Palette) -> Color {
        switch variant {
        case .neutral: return palette.brandChampagne.opacity(0.15)
        case .accent: return palette.brandChampagne.opacity(0.35)
        }
    }
}

#Preview("TagChip — variants") {
    HStack(spacing: 8) {
        TagChip(text: "meeting")
        TagChip(text: "idea", variant: .accent)
        TagChip(text: "followup")
    }
    .padding(24)
    .background(SeshatTheme.Palette.dark.appBackground)
    .preferredColorScheme(.dark)
}
