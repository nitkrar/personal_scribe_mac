import SwiftUI

@MainActor
struct PresetPickerPopover: View {
    let onPick: (Preset) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: PersonalScribeTheme.Spacing.md) {
            Text("Pick a preset")
                .font(PersonalScribeTheme.Typography.title.font)
            ForEach(Preset.allCases) { preset in
                Button {
                    onPick(preset)
                } label: {
                    HStack(alignment: .top, spacing: PersonalScribeTheme.Spacing.md) {
                        Image(systemName: preset.glyph)
                            .font(.system(size: 18, weight: .medium))
                            .frame(width: 28, height: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(preset.displayName)
                                .font(PersonalScribeTheme.Typography.body.font.weight(.medium))
                                .foregroundStyle(.primary)
                            Text(preset.subtitle)
                                .font(PersonalScribeTheme.Typography.caption.font)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.leading)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(PersonalScribeTheme.Spacing.sm)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(PersonalScribeTheme.Spacing.windowPadding)
    }
}
