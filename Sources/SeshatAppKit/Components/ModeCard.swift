import SwiftUI

/// A compact row displaying a Voice Model + AI Model preset pair, plus
/// a status pill showing whether this mode is active.
///
/// ## Scope
/// Consumed by `SettingsWindow` — specifically the Modes tab (Phase 3).
/// Depends on `StatusPill` + `SeshatTheme`. See
/// `Component_Inventory.md` row 18 / PLAN_PHASES.md Sprint 2.
///
/// ## Visual contract
/// * Left column: mode name (title) + "Voice: X · AI: Y" subtitle.
/// * Right column: `StatusPill` — `.ready` + "Active" when this mode
///   is the current one, `.neutral` + "Inactive" otherwise.
public struct ModeCard: View {
    public let modeName: String
    public let voiceModel: String
    public let aiModelPreset: String
    public let isActive: Bool

    @Environment(\.colorScheme) private var colorScheme

    public init(
        modeName: String,
        voiceModel: String,
        aiModelPreset: String,
        isActive: Bool = false
    ) {
        self.modeName = modeName
        self.voiceModel = voiceModel
        self.aiModelPreset = aiModelPreset
        self.isActive = isActive
    }

    // Exposed for tests.
    internal var subtitle: String {
        Formatters.subtitle(voiceModel: voiceModel, aiModelPreset: aiModelPreset)
    }

    internal var statusPillStatus: StatusPill.Status {
        isActive ? .ready : .neutral
    }

    internal var statusPillLabel: String {
        isActive ? "Active" : "Inactive"
    }

    public var body: some View {
        let palette = SeshatTheme.Palette.for(scheme: colorScheme)

        HStack(alignment: .center, spacing: Layout.columnSpacing) {
            VStack(alignment: .leading, spacing: Layout.innerSpacing) {
                Text(modeName)
                    .font(SeshatTheme.Typography.body.font.weight(.semibold))
                    .foregroundStyle(palette.primaryText)
                    .lineLimit(1)

                Text(subtitle)
                    .font(SeshatTheme.Typography.caption.font)
                    .foregroundStyle(palette.secondaryText)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            StatusPill(status: statusPillStatus, label: statusPillLabel)
        }
        .padding(.horizontal, SeshatTheme.Spacing.rowPadding)
        .padding(.vertical, SeshatTheme.Spacing.rowPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: SeshatTheme.Radius.row, style: .continuous)
                .fill(palette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: SeshatTheme.Radius.row, style: .continuous)
                .strokeBorder(
                    palette.brandChampagne.opacity(Layout.borderOpacity),
                    lineWidth: Layout.borderWidth
                )
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(modeName) mode, \(statusPillLabel), \(subtitle)")
    }

    // MARK: - Layout constants

    internal enum Layout {
        static let columnSpacing: CGFloat = 12
        static let innerSpacing: CGFloat = 4
        static let borderWidth: CGFloat = 0.5
        static let borderOpacity: Double = 0.15
    }

    // MARK: - Pure formatting helpers (tested)

    /// Pure helpers exposed for TDD — no SwiftUI dependency.
    public enum Formatters {
        /// Build the subtitle line: `"Voice: <voiceModel> · AI: <preset>"`.
        /// If either input is empty, fall back to an em-dash placeholder
        /// (`"—"`) for that half so the label layout stays stable.
        public static func subtitle(
            voiceModel: String,
            aiModelPreset: String
        ) -> String {
            let voice = voiceModel.isEmpty ? "\u{2014}" : voiceModel
            let ai = aiModelPreset.isEmpty ? "\u{2014}" : aiModelPreset
            return "Voice: \(voice) \u{00B7} AI: \(ai)"
        }
    }
}

#Preview("ModeCard — active + inactive") {
    VStack(spacing: SeshatTheme.Components.Preview.stackSpacing) {
        ModeCard(
            modeName: "Dictation",
            voiceModel: "Parakeet-TDT",
            aiModelPreset: "Fast rewrite",
            isActive: true
        )
        ModeCard(
            modeName: "Command",
            voiceModel: "Parakeet-TDT",
            aiModelPreset: "Instruction-following",
            isActive: false
        )
        ModeCard(
            modeName: "Notes",
            voiceModel: "Parakeet-TDT",
            aiModelPreset: "Summariser",
            isActive: false
        )
    }
    .padding(SeshatTheme.Components.Preview.canvasPadding)
    .background(SeshatTheme.Palette.dark.appBackground)
    .preferredColorScheme(.dark)
}
