import SwiftUI

/// SwiftUI view rendered inside the `ResponseCard` NSPanel for
/// Command-Mode response output (Phase 4 consumer). Adopted from
/// Claude's Sprint 2 design spec verbatim for visual fidelity.
///
/// ## Visual structure
/// Rounded 12pt rectangle, hud-material blurred background, thin
/// champagne gradient border, champagne-tinted body text, small `×`
/// dismiss button in the top-right.
///
/// Stateless: the owning `ResponseCard` panel passes in `text`, an
/// optional `link` region + `onLinkTap` handler, and an `onDismiss`
/// handler; this view has no persistent state of its own.
@MainActor
struct ResponseCardView: View {
    let text: String
    /// Stage B (#046) optional link region inside `text`. When non-nil
    /// the substring is rendered underlined and becomes tappable; tap
    /// invokes `onLinkTap(link.action)`. When nil the body renders as
    /// flat `Text` (unchanged from Stage A).
    let link: StatusCardLink?
    let onLinkTap: (@Sendable @MainActor (StatusCardLinkAction) -> Void)?
    let onDismiss: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    /// Convenience init preserving the pre-Stage-B call shape for the
    /// `#Preview` block and any text-only caller.
    init(
        text: String,
        link: StatusCardLink? = nil,
        onLinkTap: (@Sendable @MainActor (StatusCardLinkAction) -> Void)? = nil,
        onDismiss: @escaping () -> Void
    ) {
        self.text = text
        self.link = link
        self.onLinkTap = onLinkTap
        self.onDismiss = onDismiss
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // Material + fill background
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(PersonalScribeTheme.Palette.for(scheme: colorScheme).pillBackground.opacity(0.93))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    PersonalScribeTheme.Pill.Dark.waveform.opacity(0.35),
                                    Color.clear
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 0.5
                        )
                )
                .background(
                    VisualEffectBlur()
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                )

            // Body text — leading-aligned, 12pt, scheme-invariant
            // champagne fg. Hard 2-line limit keeps the card compact;
            // longer responses are truncated with an ellipsis.
            bodyText
                .font(.system(size: 12))
                .foregroundColor(PersonalScribeTheme.Pill.Dark.waveform)
                .lineSpacing(3)
                .lineLimit(2)
                .truncationMode(.tail)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Dismiss button
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(PersonalScribeTheme.Pill.Dark.cancel)
                    .padding(6)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss")
        }
        // Hard clip before shadow — same fuzzy-edge fix as the pill
        // chrome. Rounded-rect clip establishes the pixel boundary,
        // then the SwiftUI shadow composites cleanly on top.
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: .black.opacity(0.35), radius: 12, y: 4)
    }

    /// When `link` is nil the body is a plain `Text`. When a link is
    /// provided, the body is built from an `AttributedString` with the
    /// link substring underlined; the whole body reports a tap gesture
    /// that invokes the link action when the link is present.
    ///
    /// Tap-on-substring (vs. tap-on-whole-card) is out of scope for
    /// Stage B: the notification's only clickable affordance is the
    /// link text, and the card only ever renders the single
    /// notification message, so tapping anywhere on the card routes to
    /// the link action.
    @ViewBuilder
    private var bodyText: some View {
        if let link, let onLinkTap {
            Text(attributedBody(link: link))
                .contentShape(Rectangle())
                .onTapGesture {
                    onLinkTap(link.action)
                }
        } else {
            Text(text)
        }
    }

    private func attributedBody(link: StatusCardLink) -> AttributedString {
        var attributed = AttributedString(text)
        if let lower = AttributedString.Index(link.range.lowerBound, within: attributed),
           let upper = AttributedString.Index(link.range.upperBound, within: attributed) {
            attributed[lower..<upper].underlineStyle = .single
            attributed[lower..<upper].foregroundColor = PersonalScribeTheme.Pill.Dark.waveform
        }
        return attributed
    }
}

#Preview("ResponseCardView — variants") {
    VStack(spacing: 16) {
        ResponseCardView(
            text: "Q3 review is Thursday at 3pm",
            onDismiss: {}
        )
        .frame(width: 320, height: 56)

        ResponseCardView(
            text: "Here's a longer response with multiple lines of content that should wrap gracefully inside the card's 12pt radius and soft champagne border.",
            onDismiss: {}
        )
        .frame(width: 320, height: 100)
    }
    .padding()
    .background(Color.black.opacity(0.5))
    .preferredColorScheme(.dark)
}
