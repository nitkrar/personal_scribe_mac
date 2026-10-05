import PersonalScribeCore
import PersonalScribeSession
import SwiftUI

@MainActor
struct SetupView: View {
    @ObservedObject var flow: SetupFlowState
    @ObservedObject var permissions: PermissionsSubTabViewModel
    @ObservedObject var microphone: SetupMicrophoneViewModel
    @ObservedObject var model: SetupModelViewModel

    let hotkey: HotkeyPreference
    let onClose: @MainActor () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            progressHeader
            stepContent
                .padding(.top, PersonalScribeTheme.Spacing.xl)
            Spacer(minLength: PersonalScribeTheme.Spacing.lg)
            footer
        }
        .task {
            permissions.refresh()
        }
    }

    private var progressHeader: some View {
        HStack(spacing: PersonalScribeTheme.Spacing.md) {
            Text("GET STARTED · STEP \(flow.step.rawValue + 1) OF 5")
                .font(PersonalScribeTheme.Typography.sectionLabel.font)
                .foregroundStyle(palette.secondaryText)
            Spacer()
            ForEach(SetupStep.allCases, id: \.rawValue) { step in
                HStack(spacing: 6) {
                    ZStack {
                        Circle()
                            .strokeBorder(step.rawValue <= flow.step.rawValue ? palette.primaryTextBase : palette.secondaryText, lineWidth: 1)
                            .frame(width: 22, height: 22)
                        if step.rawValue < flow.step.rawValue {
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .bold))
                        } else {
                            Text("\(step.rawValue + 1)")
                                .font(.system(size: 10, weight: .semibold))
                        }
                    }
                    Text(step.title)
                        .font(PersonalScribeTheme.Typography.caption.font)
                        .foregroundStyle(step == flow.step ? palette.primaryTextBase : palette.secondaryText)
                }
            }
        }
    }

    @ViewBuilder
    private var stepContent: some View {
        switch flow.step {
        case .permissions:
            permissionsStep
        case .microphone:
            microphoneStep
        case .voiceModel:
            modelStep
        case .tryShortcut:
            shortcutStep
        case .done:
            EmptyView()
        }
    }

    private var permissionsStep: some View {
        VStack(alignment: .leading, spacing: PersonalScribeTheme.Spacing.md) {
            title("Two permissions to get started", subtitle: "Ninimma records only while you use the shortcut. Audio is transcribed on this Mac.")
            Text("REQUIRED PERMISSIONS")
                .font(PersonalScribeTheme.Typography.sectionLabel.font)
                .foregroundStyle(palette.secondaryText)
            setupPermissionRow(.microphone, title: "Microphone", icon: "mic.fill")
            setupPermissionRow(.accessibility, title: "Accessibility", icon: "accessibility.fill")
            Label("Status updates live when you return from System Settings.", systemImage: "info.circle")
                .font(PersonalScribeTheme.Typography.caption.font)
                .foregroundStyle(palette.secondaryText)
        }
    }

    private func setupPermissionRow(_ permission: Permission, title: String, icon: String) -> some View {
        HStack(spacing: PersonalScribeTheme.Spacing.md) {
            Image(systemName: icon).frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(PersonalScribeTheme.Typography.headline.font)
                Text(permissions.subtitle(for: permission))
                    .font(PersonalScribeTheme.Typography.caption.font)
                    .foregroundStyle(palette.secondaryText)
            }
            Spacer()
            Text(permissions.statusLabel(for: permission))
                .font(PersonalScribeTheme.Typography.caption.font)
                .foregroundStyle(permissions.status(for: permission) == .granted ? PersonalScribeTheme.Status.success : PersonalScribeTheme.Status.warning)
            if permissions.status(for: permission) != .granted {
                Button(permission == .microphone && permissions.status(for: permission) == .pending ? "Allow" : "Open System Settings") {
                    Task { await permissions.requestAccess(for: permission) }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(PersonalScribeTheme.Spacing.md)
        .setupCard(palette: palette)
    }

    private var microphoneStep: some View {
        VStack(alignment: .leading, spacing: PersonalScribeTheme.Spacing.lg) {
            title("Check your microphone", subtitle: "Pick the mic you'll dictate with, then say something. The meter should move.")
            Picker("Input device", selection: Binding(
                get: { microphone.selectedDeviceID },
                set: { id in Task { await microphone.selectDevice(id: id) } }
            )) {
                ForEach(microphone.devices) { device in
                    Text(device.name).tag(Optional(device.id))
                }
            }
            .labelsHidden()
            .frame(maxWidth: 420)
            VStack(alignment: .leading, spacing: PersonalScribeTheme.Spacing.md) {
                HStack {
                    Text("Say something…").font(PersonalScribeTheme.Typography.headline.font)
                    Spacer()
                    Label(microphone.level > 0.02 ? "Hearing you" : "Listening", systemImage: "circle.fill")
                        .font(PersonalScribeTheme.Typography.caption.font)
                        .foregroundStyle(PersonalScribeTheme.Status.success)
                }
                EqualizerBarsView(audioLevel: Double(microphone.level), tint: palette.brandChampagne, barCount: 20)
                    .frame(height: 52)
            }
            .padding(PersonalScribeTheme.Spacing.lg)
            .setupCard(palette: palette)
        }
        .task { await microphone.appear() }
        .onDisappear { Task { await microphone.disappear() } }
    }

    private var modelStep: some View {
        VStack(alignment: .leading, spacing: PersonalScribeTheme.Spacing.md) {
            title("Choose a voice model", subtitle: "Runs fully on-device. We picked one for this Mac — change it any time.")
            ForEach(model.models.prefix(4), id: \.id) { descriptor in
                Button {
                    model.select(descriptor)
                } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: model.selectedModel.id == descriptor.id ? "largecircle.fill.circle" : "circle")
                            Text(descriptor.displayName)
                                .font(PersonalScribeTheme.Typography.body.font.weight(.semibold))
                            if descriptor.id == model.recommendedModel.id {
                                Text("RECOMMENDED")
                                    .font(.system(size: 9, weight: .bold))
                                    .padding(.horizontal, 6).padding(.vertical, 3)
                                    .background(Capsule().fill(palette.secondaryText.opacity(0.15)))
                            }
                            Spacer()
                        }
                        Text(descriptor.shortDescription)
                            .font(PersonalScribeTheme.Typography.caption.font)
                            .foregroundStyle(palette.secondaryText)
                        if model.selectedModel.id == descriptor.id {
                            modelProgress
                        }
                    }
                    .padding(PersonalScribeTheme.Spacing.md)
                    .contentShape(Rectangle())
                    .setupCard(palette: palette, highlighted: model.selectedModel.id == descriptor.id)
                }
                .buttonStyle(.plain)
            }
            HStack {
                Button("Show all models…") { model.showAllModels() }.buttonStyle(.link)
                Spacer()
                Text("Download continues if you move on")
                    .font(PersonalScribeTheme.Typography.caption.font)
                    .foregroundStyle(palette.secondaryText)
            }
        }
        .task { await model.appear() }
    }

    @ViewBuilder
    private var modelProgress: some View {
        if let state = model.selectedState {
            switch state.phase {
            case .downloading:
                ProgressView(value: state.fractionCompleted)
            case .loading:
                ProgressView().controlSize(.small)
                Text("Preparing model…").font(PersonalScribeTheme.Typography.caption.font)
            case .ready:
                Label("Ready", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(PersonalScribeTheme.Status.success)
            case .notDownloaded:
                Text("Waiting to download…").font(PersonalScribeTheme.Typography.caption.font)
            case .failed(let message):
                Text(message).font(PersonalScribeTheme.Typography.caption.font)
                    .foregroundStyle(PersonalScribeTheme.Status.error)
            }
        }
    }

    private var shortcutStep: some View {
        VStack(alignment: .leading, spacing: PersonalScribeTheme.Spacing.lg) {
            title("Try the shortcut", subtitle: "Tap once to start and again to stop. Hold to talk, release to transcribe.")
            HStack(spacing: PersonalScribeTheme.Spacing.sm) {
                Text(HotkeyShortcutFormatter.displayString(for: hotkey))
                    .font(.system(size: 24, weight: .semibold, design: .monospaced))
                    .padding(14)
                    .setupCard(palette: palette)
                Text("Your recording shortcut")
                    .font(PersonalScribeTheme.Typography.caption.font)
                    .foregroundStyle(palette.secondaryText)
            }
            if model.isReady {
                TextEditor(text: Binding(
                    get: { flow.practiceText },
                    set: { flow.recordPracticeText($0) }
                ))
                .font(PersonalScribeTheme.Typography.body.font)
                .frame(height: 100)
                .padding(8)
                .scrollContentBackground(.hidden)
                .setupCard(palette: palette)
                .onAppear { flow.beginPractice() }
                if let result = flow.practiceResult {
                    HStack {
                        Label("It worked", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(PersonalScribeTheme.Status.success)
                        Text("\(result.wordCount) words pasted in \(result.elapsedSeconds, specifier: "%.1f") s")
                            .foregroundStyle(palette.secondaryText)
                        Spacer()
                        Button("Try again") { flow.tryPracticeAgain() }
                    }
                    .padding(PersonalScribeTheme.Spacing.md)
                    .setupCard(palette: palette, highlighted: true)
                }
            } else {
                Label("Waiting for the voice model to finish downloading", systemImage: "clock")
                    .foregroundStyle(palette.secondaryText)
                    .padding(PersonalScribeTheme.Spacing.lg)
                    .setupCard(palette: palette)
            }
        }
    }

    private var footer: some View {
        HStack {
            Button("Skip setup") {
                flow.skip(satisfaction: currentSatisfaction)
                onClose()
            }
            .buttonStyle(.link)
            Text("Menu bar works without finishing setup")
                .font(PersonalScribeTheme.Typography.caption.font)
                .foregroundStyle(palette.secondaryText)
            Spacer()
            if flow.canGoBack {
                ActionButton(title: "Back", variant: .secondary) { flow.goBack() }
            }
            ActionButton(title: "Continue") {
                flow.advance(satisfaction: currentSatisfaction)
                if !flow.isOpen { onClose() }
            }
        }
        .padding(.top, PersonalScribeTheme.Spacing.md)
        .overlay(alignment: .top) { Divider() }
    }

    private var currentSatisfaction: SetupSatisfaction {
        SetupSatisfaction(
            permissionsGranted: permissions.status(for: .microphone) == .granted
                && permissions.status(for: .accessibility) == .granted,
            modelDownloaded: model.isReady,
            shortcutTried: flow.satisfaction.shortcutTried
        )
    }

    private func title(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: PersonalScribeTheme.Spacing.sm) {
            Text(title).font(PersonalScribeTheme.Typography.largeTitle.font)
            Text(subtitle)
                .font(PersonalScribeTheme.Typography.body.font)
                .foregroundStyle(palette.secondaryText)
        }
    }

    private var palette: PersonalScribeTheme.Palette {
        PersonalScribeTheme.Palette.for(scheme: colorScheme)
    }
}

private extension View {
    func setupCard(
        palette: PersonalScribeTheme.Palette,
        highlighted: Bool = false
    ) -> some View {
        background(
            RoundedRectangle(cornerRadius: PersonalScribeTheme.Radius.md, style: .continuous)
                .fill(palette.elevatedSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: PersonalScribeTheme.Radius.md, style: .continuous)
                .strokeBorder(
                    highlighted ? palette.brandChampagne.opacity(0.8) : palette.secondaryText.opacity(0.15),
                    lineWidth: highlighted ? 1 : 0.5
                )
        )
    }
}
