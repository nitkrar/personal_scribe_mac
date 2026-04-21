import PersonalScribeCore
import SwiftUI

/// Settings → Permissions sub-tab for the unified window.
///
/// Replaces the standalone Onboarding window's permissions UI with a
/// card-row layout. Each row shows a current status dot
/// (green = granted, orange = warning) and a blue "Grant Access" button
/// that deep-links into the relevant Privacy pane in System Settings.
///
/// Reference: `plans/App UI design/Claude_Final_Bundle_Prompt.md` §3D.
@MainActor
struct PermissionsSubTab: View {
    @ObservedObject var viewModel: PermissionsSubTabViewModel

    @Environment(\.colorScheme) private var colorScheme

    init(viewModel: PermissionsSubTabViewModel) {
        self.viewModel = viewModel
    }

    var body: some View {
        let palette = PersonalScribeTheme.Palette.for(scheme: colorScheme)

        VStack(alignment: .leading, spacing: PersonalScribeTheme.Spacing.md) {
            Text("Required permissions")
                .font(PersonalScribeTheme.Typography.sectionLabel.font)
                .textCase(.uppercase)
                .foregroundStyle(palette.secondaryText)

            PermissionRow(
                permission: .microphone,
                systemImageName: "mic.fill",
                title: "Microphone",
                subtitle: "Capture audio for transcription.",
                status: viewModel.status(for: .microphone),
                grantAction: { viewModel.grantAccess(for: .microphone) }
            )

            PermissionRow(
                permission: .inputMonitoring,
                systemImageName: "keyboard.fill",
                title: "Input Monitoring",
                subtitle: "Detect the global double-tap option hotkey.",
                status: viewModel.status(for: .inputMonitoring),
                grantAction: { viewModel.grantAccess(for: .inputMonitoring) }
            )

            PermissionRow(
                permission: .accessibility,
                systemImageName: "accessibility.fill",
                title: "Accessibility",
                subtitle: "Paste transcripts into the current app.",
                status: viewModel.status(for: .accessibility),
                grantAction: { viewModel.grantAccess(for: .accessibility) }
            )
        }
        .onAppear {
            viewModel.refresh()
        }
    }
}

// MARK: - Row

private struct PermissionRow: View {
    let permission: Permission
    let systemImageName: String
    let title: String
    let subtitle: String
    let status: PermissionStatus
    let grantAction: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.windowTint) private var windowTint

    var body: some View {
        let palette = PersonalScribeTheme.Palette.for(scheme: colorScheme)
        let background = windowTint?.cardBackground ?? palette.elevatedSurface

        HStack(alignment: .center, spacing: PersonalScribeTheme.Spacing.md) {
            Image(systemName: systemImageName)
                .font(.system(size: 18, weight: .semibold))
                .frame(width: 28, alignment: .center)

            VStack(alignment: .leading, spacing: PersonalScribeTheme.Spacing.xs) {
                Text(title)
                    .font(PersonalScribeTheme.Typography.headline.font)

                Text(subtitle)
                    .font(PersonalScribeTheme.Typography.caption.font)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            statusDot

            if status != .granted {
                Button("Grant Access", action: grantAction)
                    .buttonStyle(.plain)
                    .foregroundStyle(PersonalScribeTheme.Status.link)
                    .font(PersonalScribeTheme.Typography.body.font.weight(.semibold))
            }
        }
        .padding(.horizontal, PersonalScribeTheme.Spacing.md)
        .padding(.vertical, PersonalScribeTheme.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: PersonalScribeTheme.Radius.md, style: .continuous)
                .fill(background)
        )
        .overlay(
            RoundedRectangle(cornerRadius: PersonalScribeTheme.Radius.md, style: .continuous)
                .strokeBorder(
                    palette.brandChampagne.opacity(0.12),
                    lineWidth: 0.5
                )
        )
    }

    private var statusDot: some View {
        Circle()
            .fill(dotColor)
            .frame(width: 8, height: 8)
    }

    private var dotColor: Color {
        switch status {
        case .granted:
            return PersonalScribeTheme.Status.success
        case .pending, .denied:
            return PersonalScribeTheme.Status.warning
        }
    }
}
