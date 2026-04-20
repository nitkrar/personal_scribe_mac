import PersonalScribeCore
import SwiftUI

@MainActor
struct AboutSubTab: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = PersonalScribeTheme.Palette.for(scheme: colorScheme)

        VStack {
            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: PersonalScribeTheme.Spacing.md) {
                HStack(spacing: PersonalScribeTheme.Spacing.md) {
                    PersonalScribeLogoView()
                        .frame(width: 48, height: 48)

                    Text(AppBrand.displayName)
                        .font(PersonalScribeTheme.Typography.largeTitle.font)
                        .foregroundStyle(palette.primaryText)
                }

                VStack(alignment: .leading, spacing: PersonalScribeTheme.Spacing.sm) {
                    infoRow(
                        title: "Version",
                        value: AppBrand.version,
                        palette: palette
                    )
                    infoRow(
                        title: "Build",
                        value: AppBrand.buildNumber,
                        palette: palette
                    )
                    infoRow(
                        title: "Bundle identifier",
                        value: AppBrand.bundleIdentifier,
                        usesMonospacedValue: true,
                        palette: palette
                    )
                }

                Text("© 2026 Nitin Kumar. All rights reserved.")
                    .font(PersonalScribeTheme.Typography.caption.font)
                    .foregroundStyle(palette.secondaryText)
                    .padding(.top, PersonalScribeTheme.Spacing.sm)
            }
            .padding(PersonalScribeTheme.Spacing.lg)
            .frame(
                maxWidth: cardWidth,
                alignment: .leading
            )
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
                    PersonalScribeTheme.Separator.primary.opacity(0.4),
                    lineWidth: 1
                )
            }
            .padding(PersonalScribeTheme.Spacing.lg)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var cardWidth: CGFloat {
        min(
            480,
            PersonalScribeTheme.Layout.windowMinWidth - (PersonalScribeTheme.Spacing.lg * 2)
        )
    }

    private func infoRow(
        title: String,
        value: String,
        usesMonospacedValue: Bool = false,
        palette: PersonalScribeTheme.Palette
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: PersonalScribeTheme.Spacing.md) {
            Text(title)
                .font(PersonalScribeTheme.Typography.headline.font)
                .foregroundStyle(palette.primaryText)
                .frame(width: 140, alignment: .leading)

            Text(value)
                .font(valueFont(usesMonospacedValue: usesMonospacedValue))
                .foregroundStyle(palette.secondaryTextBase.opacity(0.8))
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
    }

    private func valueFont(usesMonospacedValue: Bool) -> Font {
        if usesMonospacedValue {
            return .system(
                size: PersonalScribeTheme.Typography.body.pointSize,
                weight: PersonalScribeTheme.Typography.body.weight,
                design: .monospaced
            )
        }

        return PersonalScribeTheme.Typography.body.font
    }
}
