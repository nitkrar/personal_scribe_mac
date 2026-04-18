import SwiftUI

/// Temporary overlay card shown above the pill for Command Mode responses.
///
/// Reference: `plans/seshat_agent_bundle/03_Surfaces/PillOverlayWindow/command_mode_states.png`.
/// PANEL 2 (processing / "Opening Safari…"), PANEL 3 (query response with
/// text answer), PANEL 4 (action confirmation toast) all share this
/// surface — Sprint 2's B1a stub-build ships the text-answer variant
/// (title + body) and leaves the action buttons / icons for Phase 3.
///
/// ## Responsibilities
/// * Render a `title` (optional — may be empty string) and `body` in the
///   champagne-palette surface.
/// * Expose an `accessibilityDescription` string so tests and VoiceOver
///   can verify the composed label without reflecting into the SwiftUI
///   render tree.
///
/// ## Non-responsibilities
/// The card is **stateless**. It does NOT own visibility, auto-dismiss
/// timing, or transition animations — the pill presenter decides when
/// to show and hide it.
///
/// ## Sprint 2 scope
/// Per Phase 2 Sprint 2 Agent 1 contract, this file is the first piece
/// of the B1 lane (ResponseCard has no external dependencies) and is
/// built before the pill rewrite.
public struct ResponseCard: View {
    public let title: String
    public let body: String

    @Environment(\.colorScheme) private var colorScheme

    public init(title: String, body: String) {
        self.title = title
        self.body = body
    }

    /// Composed accessibility label. Tests read this directly rather
    /// than attempting to reflect into the SwiftUI render tree.
    public var accessibilityDescription: String {
        let trimmedTitle = title.trimmingCharacters(in: .whitespaces)
        if trimmedTitle.isEmpty {
            return body
        }
        return "\(trimmedTitle). \(body)"
    }

    public var body: some View {
        let palette = SeshatTheme.Palette.for(scheme: colorScheme)
        let hasTitle = !title.trimmingCharacters(in: .whitespaces).isEmpty

        HStack(alignment: .top, spacing: SeshatTheme.Spacing.iconPadding) {
            SeshatLogoView(size: 20, state: .idle)
                .frame(width: 20, height: 20)

            VStack(alignment: .leading, spacing: 4) {
                if hasTitle {
                    Text(title)
                        .font(SeshatTheme.Typography.caption.font)
                        .foregroundStyle(palette.secondaryText)
                }

                Text(self.body)
                    .font(SeshatTheme.Typography.body.font)
                    .foregroundStyle(palette.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, SeshatTheme.Spacing.rowPadding)
        .padding(.vertical, SeshatTheme.Spacing.iconPadding)
        .background(
            RoundedRectangle(cornerRadius: SeshatTheme.Radius.row, style: .continuous)
                .fill(palette.elevatedSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: SeshatTheme.Radius.row, style: .continuous)
                .strokeBorder(
                    palette.brandChampagne.opacity(0.18),
                    lineWidth: 0.5
                )
        )
        .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
    }
}

#Preview("ResponseCard — variants") {
    VStack(spacing: SeshatTheme.Components.Preview.stackSpacing) {
        ResponseCard(
            title: "From your notes",
            body: "Q3 review is Thursday at 3pm"
        )

        ResponseCard(
            title: "",
            body: "Copied to clipboard"
        )
    }
    .padding(SeshatTheme.Components.Preview.canvasPadding)
    .background(SeshatTheme.Palette.dark.appBackground)
    .preferredColorScheme(.dark)
}
