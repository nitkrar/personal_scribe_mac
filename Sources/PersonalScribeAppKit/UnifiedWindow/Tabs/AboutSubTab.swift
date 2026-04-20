import PersonalScribeCore
import SwiftUI

/// About sub-tab inside Settings.
///
/// ## Design (2026-04-20)
/// Centred card layout:
///   • App icon + name + tagline (tight vertical stack — brand moment)
///   • Thin champagne divider
///   • Version / Build in a two-column row (bundle ID removed — not
///     relevant to end users)
///   • ORIGIN section: two-sentence scribe-focused copy + mythlok link
///   • Copyright footer
@MainActor
struct AboutSubTab: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = PersonalScribeTheme.Palette.for(scheme: colorScheme)

        VStack {
            Spacer(minLength: 0)

            VStack(alignment: .center, spacing: 0) {

                // MARK: Brand header — icon + name + tagline
                PersonalScribeLogoView()
                    .frame(width: 64, height: 64)

                Text(AppBrand.displayName)
                    .font(PersonalScribeTheme.Typography.largeTitle.font)
                    .foregroundStyle(palette.primaryText)
                    .padding(.top, PersonalScribeTheme.Spacing.sm)

                // Tagline sits directly under the name — 4pt gap.
                Text(AppBrand.tagline)
                    .font(.system(
                        size: PersonalScribeTheme.Typography.body.pointSize,
                        weight: .regular,
                        design: .default
                    ).italic())
                    .foregroundStyle(palette.brandChampagne)
                    .multilineTextAlignment(.center)
                    .padding(.top, 4)

                // MARK: Divider
                Rectangle()
                    .fill(palette.brandChampagne.opacity(0.25))
                    .frame(height: 1)
                    .padding(.vertical, PersonalScribeTheme.Spacing.md)

                // MARK: Version / Build row
                HStack(spacing: 0) {
                    versionItem(
                        label: "Version",
                        value: AppBrand.version,
                        palette: palette
                    )
                    Spacer()
                    versionItem(
                        label: "Build",
                        value: AppBrand.buildNumber,
                        palette: palette
                    )
                }
                .padding(.bottom, PersonalScribeTheme.Spacing.md)

                // MARK: Origin section
                VStack(alignment: .leading, spacing: PersonalScribeTheme.Spacing.xs) {
                    Text("ORIGIN")
                        .font(.system(
                            size: 11,
                            weight: .semibold
                        ))
                        .foregroundStyle(palette.brandChampagne)
                        .kerning(0.5)

                    Text(AppBrand.originStory)
                        .font(PersonalScribeTheme.Typography.body.font)
                        .foregroundStyle(palette.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    // Tappable link to mythlok.com
                    Link(destination: URL(string: "https://mythlok.com/ninimma/")!) {
                        HStack(spacing: 4) {
                            Text("Learn more at mythlok.com")
                            Image(systemName: "arrow.right")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .font(PersonalScribeTheme.Typography.body.font)
                        .foregroundStyle(palette.statusLink)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, PersonalScribeTheme.Spacing.md)

                // MARK: Copyright
                Text("© 2026 Nitin Kumar. All rights reserved.")
                    .font(PersonalScribeTheme.Typography.caption.font)
                    .foregroundStyle(palette.secondaryText.opacity(0.7))
                    .multilineTextAlignment(.center)
            }
            .padding(PersonalScribeTheme.Spacing.lg)
            .frame(maxWidth: cardWidth, alignment: .center)
            .background(
                RoundedRectangle(
                    cornerRadius: PersonalScribeTheme.Radius.lg,
                    style: .continuous
                )
                .fill(palette.elevatedSurface)
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: PersonalScribeTheme.Radius.lg,
                    style: .continuous
                )
                .stroke(
                    palette.brandChampagne.opacity(0.15),
                    lineWidth: 1
                )
            }
            .padding(PersonalScribeTheme.Spacing.lg)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Helpers

    private var cardWidth: CGFloat {
        min(
            480,
            PersonalScribeTheme.Layout.windowMinWidth - (PersonalScribeTheme.Spacing.lg * 2)
        )
    }

    @ViewBuilder
    private func versionItem(
        label: String,
        value: String,
        palette: PersonalScribeTheme.Palette
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(palette.secondaryText)
            Text(value)
                .font(PersonalScribeTheme.Typography.body.font)
                .foregroundStyle(palette.primaryText)
        }
    }
}
