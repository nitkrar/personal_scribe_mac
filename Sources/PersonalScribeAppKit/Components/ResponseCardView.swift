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
/// Stateless: the owning `ResponseCard` panel passes in `text` and an
/// `onDismiss` handler; this view has no persistent state of its own.
@MainActor
struct ResponseCardView: View {
    let text: String
    let onDismiss: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = PersonalScribeTheme.Palette.for(scheme: colorScheme)

        ZStack(alignment: .topTrailing) {
            // Material + fill background
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(palette.pillBackground.opacity(0.93))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    palette.brandChampagne.opacity(0.4),
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

            // Body text — leading-aligned, 13pt, champagne/cream
            Text(text)
                .font(.system(size: 13))
                .foregroundColor(palette.pillForegroundText)
                .lineSpacing(4)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Dismiss button
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(palette.brandChampagne.opacity(0.6))
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
