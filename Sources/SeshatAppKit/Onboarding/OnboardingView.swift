import SwiftUI

struct OnboardingView: View {
    @ObservedObject var viewModel: OnboardingViewModel

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = SeshatTheme.Palette.for(scheme: colorScheme)

        VStack(alignment: .leading, spacing: 20) {
            header(palette: palette)
            paneContent(palette: palette)
            Spacer(minLength: 0)
        }
        .padding(SeshatTheme.Spacing.windowPadding)
        .frame(minWidth: 520, minHeight: 360, alignment: .topLeading)
        .background(palette.appBackground)
    }

    @ViewBuilder
    private func paneContent(palette: SeshatTheme.Palette) -> some View {
        switch viewModel.currentPane {
        case .welcome:
            VStack(alignment: .leading, spacing: 16) {
                Text("Seshat needs three permissions before first use.")
                    .font(SeshatTheme.Typography.body.font)
                    .foregroundStyle(palette.primaryText)

                Text("We request microphone, Input Monitoring, and Accessibility in order so recording, hotkeys, and paste all work before the pill or menu try to use them.")
                    .font(SeshatTheme.Typography.body.font)
                    .foregroundStyle(palette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                ActionButton(title: "Continue") {
                    viewModel.advance()
                }
            }
        case .microphone:
            permissionPane(
                title: "Microphone",
                body: "Microphone access lets Seshat capture dictation.",
                outcome: viewModel.microphoneOutcome,
                grantTitle: "Grant Microphone"
            ) {
                await viewModel.requestCurrentPermission()
            } skipAction: {
                viewModel.skipCurrentPermission()
            }
        case .inputMonitoring:
            permissionPane(
                title: "Input Monitoring",
                body: "Input Monitoring is required for the global hotkey and for listening before the pill tries to record.",
                outcome: viewModel.inputMonitoringOutcome,
                grantTitle: "Grant Input Monitoring"
            ) {
                await viewModel.requestCurrentPermission()
            } skipAction: {
                viewModel.skipCurrentPermission()
            }
        case .accessibility:
            permissionPane(
                title: "Accessibility",
                body: "Accessibility is required to paste the transcript back into the frontmost app after transcription finishes.",
                outcome: viewModel.accessibilityOutcome,
                grantTitle: "Grant Accessibility"
            ) {
                await viewModel.requestCurrentPermission()
            } skipAction: {
                viewModel.skipCurrentPermission()
            }
        case .done:
            VStack(alignment: .leading, spacing: 12) {
                Text("Setup complete.")
                    .font(SeshatTheme.Typography.body.font.weight(.semibold))
                    .foregroundStyle(palette.primaryText)

                Text("Closing onboarding.")
                    .font(SeshatTheme.Typography.body.font)
                    .foregroundStyle(palette.secondaryText)
            }
        }
    }

    private func header(palette: SeshatTheme.Palette) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Welcome to Seshat")
                .font(SeshatTheme.Typography.display.font)
                .foregroundStyle(palette.primaryText)

            Text("First-run setup")
                .font(SeshatTheme.Typography.caption.font)
                .foregroundStyle(palette.secondaryText)
                .textCase(.uppercase)
        }
    }

    private func permissionPane(
        title: String,
        body: String,
        outcome: OnboardingPermissionOutcome,
        grantTitle: String,
        grantAction: @escaping @MainActor () async -> Void,
        skipAction: @escaping @MainActor () -> Void
    ) -> some View {
        let palette = SeshatTheme.Palette.for(scheme: colorScheme)

        return VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 12) {
                Text(title)
                    .font(SeshatTheme.Typography.body.font.weight(.semibold))
                    .foregroundStyle(palette.primaryText)

                statusBadge(for: outcome, palette: palette)
            }

            Text(body)
                .font(SeshatTheme.Typography.body.font)
                .foregroundStyle(palette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 12) {
                ActionButton(title: grantTitle) {
                    Task { @MainActor in
                        await grantAction()
                    }
                }

                ActionButton(title: "Skip", variant: .secondary) {
                    skipAction()
                }
            }
        }
        .padding(SeshatTheme.Spacing.rowPadding)
        .background(
            RoundedRectangle(cornerRadius: SeshatTheme.Radius.window, style: .continuous)
                .fill(palette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: SeshatTheme.Radius.window, style: .continuous)
                .strokeBorder(
                    palette.brandChampagne.opacity(0.15),
                    lineWidth: 0.5
                )
        )
    }

    private func statusBadge(
        for outcome: OnboardingPermissionOutcome,
        palette: SeshatTheme.Palette
    ) -> some View {
        Text(outcome.badgeTitle)
            .font(SeshatTheme.Typography.caption.font.weight(.semibold))
            .foregroundStyle(badgeForegroundColor(for: outcome, palette: palette))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule(style: .continuous)
                    .fill(badgeBackgroundColor(for: outcome, palette: palette))
            )
    }

    private func badgeBackgroundColor(
        for outcome: OnboardingPermissionOutcome,
        palette: SeshatTheme.Palette
    ) -> Color {
        switch outcome {
        case .pending:
            return palette.elevatedSurface
        case .granted:
            return palette.statusReady.opacity(0.18)
        case .denied:
            return palette.statusRecording.opacity(0.18)
        case .skipped:
            return palette.brandChampagne.opacity(0.18)
        }
    }

    private func badgeForegroundColor(
        for outcome: OnboardingPermissionOutcome,
        palette: SeshatTheme.Palette
    ) -> Color {
        switch outcome {
        case .pending:
            return palette.secondaryText
        case .granted:
            return palette.statusReady
        case .denied:
            return palette.statusRecording
        case .skipped:
            return palette.brandChampagne
        }
    }
}

private extension OnboardingPermissionOutcome {
    var badgeTitle: String {
        switch self {
        case .pending:
            "Pending"
        case .granted:
            "Granted"
        case .denied:
            "Denied"
        case .skipped:
            "Skipped"
        }
    }
}
