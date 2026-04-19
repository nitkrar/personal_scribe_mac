import SwiftUI

struct OnboardingView: View {
    @ObservedObject var viewModel: OnboardingViewModel

    @Environment(\.openURL) private var openURL

    @State private var isMicrophoneInfoPresented = false
    @State private var isInputMonitoringInfoPresented = false
    @State private var isAccessibilityInfoPresented = false

    private let palette = SeshatTheme.Palette.for(scheme: .dark)
    private let warningColor = Color.yellow

    var body: some View {
        VStack(spacing: 14) {
            header
            checklist
            Spacer(minLength: 0)
            footer
        }
        .padding(.top, 14)
        .padding(.horizontal, 22)
        .padding(.bottom, 16)
        .frame(minWidth: 520, maxWidth: .infinity, minHeight: 360, maxHeight: .infinity, alignment: .top)
        .background(backgroundView)
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(palette.brandChampagne.opacity(0.18))
                    .frame(width: 74, height: 74)
                    .blur(radius: 16)

                SeshatLogoView(color: palette.brandChampagne)
                    .frame(width: 46, height: 46)
            }
            .frame(maxWidth: .infinity)

            Text("Welcome to Seshat")
                .font(SeshatTheme.Typography.display.font)
                .foregroundStyle(palette.primaryText)

            Text("Your personal AI scribe")
                .font(SeshatTheme.Typography.body.font)
                .foregroundStyle(palette.secondaryText)
        }
        .frame(maxWidth: .infinity)
    }

    private var checklist: some View {
        VStack(spacing: 8) {
            permissionRow(
                index: 1,
                title: "Microphone Access",
                oneLiner: "Capture audio for transcription.",
                popoverCopy: "Seshat only uses the microphone while you are actively recording. Audio never leaves your device — transcription runs locally via Parakeet-TDT.",
                outcome: viewModel.microphoneOutcome,
                isOptional: false,
                showsConnector: true,
                isInfoPresented: $isMicrophoneInfoPresented,
                grantAction: {
                    Task { @MainActor in
                        await viewModel.requestMicrophoneAccess()
                    }
                },
                settingsAnchor: "Privacy_Microphone"
            )

            permissionRow(
                index: 2,
                title: "Input Monitoring",
                oneLiner: "Detect the global double-tap ⌥ hotkey.",
                popoverCopy: "Input Monitoring lets Seshat see option-key taps even when another app is focused. Without it, the hotkey will not work.",
                outcome: viewModel.inputMonitoringOutcome,
                isOptional: false,
                showsConnector: true,
                isInfoPresented: $isInputMonitoringInfoPresented,
                grantAction: {
                    Task { @MainActor in
                        await viewModel.requestInputMonitoringAccess()
                    }
                },
                settingsAnchor: "Privacy_ListenEvent"
            )

            permissionRow(
                index: 3,
                title: "Accessibility",
                oneLiner: "Paste transcripts into the current app.",
                popoverCopy: "Accessibility lets Seshat paste transcripts into the app you were typing in. Without Accessibility, Seshat still copies every transcript to your clipboard — you can paste manually with ⌘V.",
                outcome: viewModel.accessibilityOutcome,
                isOptional: true,
                showsConnector: false,
                isInfoPresented: $isAccessibilityInfoPresented,
                grantAction: {
                    Task { @MainActor in
                        await viewModel.requestAccessibilityAccess()
                    }
                },
                skipAction: {
                    viewModel.skipAccessibilityAccess()
                },
                settingsAnchor: "Privacy_Accessibility"
            )
        }
    }

    private var footer: some View {
        VStack(spacing: 8) {
            if viewModel.canContinue == false {
                Text("Grant Microphone and Input Monitoring to continue.")
                    .font(SeshatTheme.Typography.caption.font)
                    .foregroundStyle(palette.secondaryText)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }

            Text("AI model: Parakeet TDT 0.6B · configure in Settings")
                .font(SeshatTheme.Typography.caption.font)
                .foregroundStyle(palette.secondaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

            Text("Transcripts always copy to clipboard regardless.")
                .font(SeshatTheme.Typography.caption.font)
                .foregroundStyle(palette.secondaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

            continueButton

            Button("Skip setup") {
                viewModel.skipSetupTapped()
            }
            .font(SeshatTheme.Typography.body.font.weight(.medium))
            .foregroundStyle(palette.brandChampagne)
            .buttonStyle(.plain)
        }
    }

    private var continueButton: some View {
        Button {
            viewModel.continueTapped()
        } label: {
            Text("Continue")
                .font(SeshatTheme.Typography.body.font.weight(.semibold))
                .foregroundStyle(SeshatTheme.Palette.dark.appBackground)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, SeshatTheme.Components.ActionButton.horizontalPadding)
                .padding(.vertical, SeshatTheme.Components.ActionButton.verticalPadding)
                .background(
                    RoundedRectangle(cornerRadius: SeshatTheme.Radius.row, style: .continuous)
                        .fill(palette.brandChampagne)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: SeshatTheme.Radius.row, style: .continuous)
                        .strokeBorder(
                            palette.brandChampagne.opacity(
                                SeshatTheme.Components.ActionButton.primaryBorderOpacity
                            ),
                            lineWidth: SeshatTheme.Components.ActionButton.borderWidth
                        )
                )
                .opacity(
                    viewModel.canContinue
                    ? 1.0
                    : SeshatTheme.Components.ActionButton.disabledOpacity
                )
        }
        .buttonStyle(.plain)
        .disabled(viewModel.canContinue == false)
    }

    private var backgroundView: some View {
        ZStack {
            palette.appBackground

            LinearGradient(
                colors: [
                    palette.appBackground,
                    palette.surface.opacity(0.7)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            RadialGradient(
                colors: [
                    palette.brandChampagne.opacity(0.12),
                    palette.appBackground.opacity(0)
                ],
                center: .top,
                startRadius: 8,
                endRadius: 180
            )
            .offset(y: -24)
        }
    }

    private func permissionRow(
        index: Int,
        title: String,
        oneLiner: String,
        popoverCopy: String,
        outcome: OnboardingPermissionOutcome,
        isOptional: Bool,
        showsConnector: Bool,
        isInfoPresented: Binding<Bool>,
        grantAction: @escaping () -> Void,
        skipAction: (() -> Void)? = nil,
        settingsAnchor: String
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            iconColumn(
                index: index,
                outcome: outcome,
                isOptional: isOptional,
                showsConnector: showsConnector
            )

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(title)
                        .font(SeshatTheme.Typography.body.font.weight(.semibold))
                        .foregroundStyle(palette.primaryText)

                    if isOptional {
                        optionalBadge
                    }

                    Button {
                        isInfoPresented.wrappedValue = true
                    } label: {
                        Image(systemName: "info.circle")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(palette.secondaryText)
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: isInfoPresented, arrowEdge: .top) {
                        infoPopover(title: title, copy: popoverCopy)
                    }
                }

                Text(oneLiner)
                    .font(SeshatTheme.Typography.caption.font)
                    .foregroundStyle(palette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                if isOptional && viewModel.showsAccessibilityWarning {
                    Text("Seshat will not be able to paste into other apps. Transcripts still copy to clipboard.")
                        .font(SeshatTheme.Typography.caption.font)
                        .foregroundStyle(warningColor)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            statusControl(
                outcome: outcome,
                isOptional: isOptional,
                grantAction: grantAction,
                skipAction: skipAction,
                settingsAnchor: settingsAnchor
            )
        }
        .padding(.vertical, 2)
    }

    private func iconColumn(
        index: Int,
        outcome: OnboardingPermissionOutcome,
        isOptional: Bool,
        showsConnector: Bool
    ) -> some View {
        VStack(spacing: 4) {
            rowIcon(index: index, outcome: outcome, isOptional: isOptional)

            if showsConnector {
                Rectangle()
                    .fill(palette.hoverState)
                    .frame(width: 1, height: 20)
            }
        }
        .frame(width: 22)
    }

    @ViewBuilder
    private func rowIcon(
        index: Int,
        outcome: OnboardingPermissionOutcome,
        isOptional: Bool
    ) -> some View {
        if outcome == .granted {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(palette.statusReady)
        } else if isOptional && (outcome == .denied || outcome == .skipped) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(warningColor)
                .padding(.top, 1)
        } else {
            Image(systemName: "\(index).circle.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(numberColor(isOptional: isOptional))
        }
    }

    private func numberColor(isOptional: Bool) -> Color {
        isOptional ? palette.secondaryText : palette.statusLink
    }

    @ViewBuilder
    private func statusControl(
        outcome: OnboardingPermissionOutcome,
        isOptional: Bool,
        grantAction: @escaping () -> Void,
        skipAction: (() -> Void)?,
        settingsAnchor: String
    ) -> some View {
        switch outcome {
        case .pending:
            if isOptional, let skipAction {
                VStack(alignment: .trailing, spacing: 4) {
                    ActionButton(title: "Grant", action: grantAction)

                    Button("Skip") {
                        skipAction()
                    }
                    .font(SeshatTheme.Typography.caption.font.weight(.semibold))
                    .foregroundStyle(warningColor)
                    .buttonStyle(.plain)
                }
            } else {
                ActionButton(title: "Grant", action: grantAction)
            }
        case .granted:
            Text("Granted")
                .font(SeshatTheme.Typography.body.font.weight(.semibold))
                .foregroundStyle(palette.statusReady)
        case .denied:
            Button("Open Settings") {
                openPrivacySettings(anchor: settingsAnchor)
            }
            .font(SeshatTheme.Typography.body.font.weight(.semibold))
            .foregroundStyle(palette.statusLink)
            .buttonStyle(.plain)
        case .skipped:
            Text("Skipped")
                .font(SeshatTheme.Typography.body.font.weight(.semibold))
                .foregroundStyle(warningColor)
        }
    }

    private var optionalBadge: some View {
        Text("Optional")
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(palette.primaryText.opacity(0.8))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule(style: .continuous)
                    .fill(palette.elevatedSurface)
            )
    }

    private func infoPopover(title: String, copy: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(SeshatTheme.Typography.body.font.weight(.semibold))
                .foregroundStyle(palette.primaryText)

            Text(copy)
                .font(SeshatTheme.Typography.body.font)
                .foregroundStyle(palette.primaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(width: 280, alignment: .leading)
        .background(palette.surface)
    }

    private func openPrivacySettings(anchor: String) {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)"
        ) else {
            return
        }

        openURL(url)
    }
}
