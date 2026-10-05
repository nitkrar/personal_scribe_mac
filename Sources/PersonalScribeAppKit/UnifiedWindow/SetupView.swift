import AppKit
import PersonalScribeCore
import PersonalScribeSession
import SwiftUI

@MainActor
struct SetupView: View {
    @ObservedObject var flow: SetupFlowState
    @ObservedObject var permissions: PermissionsSubTabViewModel
    let microphone: SetupMicrophoneViewModel
    @ObservedObject var model: SetupModelViewModel
    @ObservedObject var checklist: HomeChecklistState
    @StateObject private var pillPreview: PillOverlayViewModel

    let onOpenShortcuts: @MainActor () -> Void
    let onClose: @MainActor () -> Void

    @Environment(\.colorScheme) private var colorScheme

    init(
        flow: SetupFlowState,
        permissions: PermissionsSubTabViewModel,
        microphone: SetupMicrophoneViewModel,
        model: SetupModelViewModel,
        checklist: HomeChecklistState,
        pillPreviewRenderDate: Date? = nil,
        onOpenShortcuts: @escaping @MainActor () -> Void,
        onClose: @escaping @MainActor () -> Void
    ) {
        self.flow = flow
        self.permissions = permissions
        self.microphone = microphone
        self.model = model
        self.checklist = checklist
        self.onOpenShortcuts = onOpenShortcuts
        self.onClose = onClose
        let preview = PillOverlayViewModel(visibility: .recording)
        preview.waveformRenderDate = pillPreviewRenderDate
        _pillPreview = StateObject(wrappedValue: preview)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            progressHeader
            stepContent
                .padding(.top, PersonalScribeTheme.Spacing.xl)
            Spacer(minLength: PersonalScribeTheme.Spacing.lg)
            if flow.step == .tryShortcut, model.isReady, flow.practiceResult == nil {
                SetupMicrophoneObserver(microphone: microphone) {
                    practicePillPreview
                }
                .padding(.bottom, PersonalScribeTheme.Spacing.md)
            }
            footer
        }
        .task {
            permissions.refresh()
        }
    }

    private var progressHeader: some View {
        HStack(alignment: .center, spacing: 16) {
            Text("GET STARTED · STEP \(flow.step.rawValue + 1) OF 5")
                .font(PersonalScribeTheme.Typography.sectionLabel.font)
                .foregroundStyle(palette.secondaryText)
                .fixedSize()
            Spacer(minLength: 8)
            HStack(spacing: 4) {
                ForEach(SetupStep.allCases, id: \.rawValue) { step in
                    HStack(spacing: 4) {
                        ZStack {
                            if step.rawValue < flow.step.rawValue {
                                Circle()
                                    .fill(palette.brandChampagne)
                                Image(systemName: "checkmark")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(PersonalScribeTheme.Palette.dark.appBackground)
                            } else {
                                Circle()
                                    .strokeBorder(
                                        step == flow.step ? palette.primaryTextBase : palette.secondaryText,
                                        lineWidth: 1
                                    )
                                Text("\(step.rawValue + 1)")
                                    .font(.system(size: 9, weight: .semibold))
                            }
                        }
                        .frame(width: 18, height: 18)
                        Text(step.title)
                            .font(PersonalScribeTheme.Typography.caption.font)
                            .foregroundStyle(step == flow.step ? palette.primaryTextBase : palette.secondaryText)
                            .fixedSize()
                        if step != SetupStep.allCases.last {
                            Rectangle()
                                .fill(palette.secondaryText.opacity(0.35))
                                .frame(width: 18, height: 1)
                                .fixedSize()
                        }
                    }
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
            SetupMicrophoneObserver(microphone: microphone) {
                microphoneStep
            }
        case .voiceModel:
            modelStep
        case .tryShortcut:
            SetupMicrophoneObserver(microphone: microphone) {
                shortcutStep
            }
        case .done:
            EmptyView()
        }
    }

    private var permissionsStep: some View {
        VStack(alignment: .leading, spacing: PersonalScribeTheme.Spacing.md) {
            title("Microphone access to get started", subtitle: "Ninimma records only while you use the shortcut. Audio is transcribed on this Mac.")
            Text("REQUIRED")
                .font(PersonalScribeTheme.Typography.sectionLabel.font)
                .foregroundStyle(palette.secondaryText)
            setupPermissionRow(.microphone, title: "Microphone", icon: "mic.fill")
            Text("OPTIONAL")
                .font(PersonalScribeTheme.Typography.sectionLabel.font)
                .foregroundStyle(palette.secondaryText)
            setupPermissionRow(
                .accessibility,
                title: "Accessibility",
                icon: "accessibility.fill",
                subtitle: "Auto-pastes text; without it, text is left on the clipboard."
            )
            Label("Accessibility can also be granted later in Settings → Permissions.", systemImage: "info.circle")
                .font(PersonalScribeTheme.Typography.caption.font)
                .foregroundStyle(palette.secondaryText)
        }
    }

    private func setupPermissionRow(
        _ permission: Permission,
        title: String,
        icon: String,
        subtitle: String? = nil
    ) -> some View {
        HStack(spacing: PersonalScribeTheme.Spacing.md) {
            Image(systemName: icon).frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(PersonalScribeTheme.Typography.headline.font)
                Text(subtitle ?? permissions.subtitle(for: permission))
                    .font(PersonalScribeTheme.Typography.caption.font)
                    .foregroundStyle(palette.secondaryText)
            }
            Spacer()
            HStack(spacing: 6) {
                Circle()
                    .fill(permissionStatusColor(permission))
                    .frame(width: 8, height: 8)
                Text(permissionStatusLabel(permission))
            }
            .font(PersonalScribeTheme.Typography.caption.font)
            .foregroundStyle(permissionStatusColor(permission))
            if permissions.status(for: permission) != .granted {
                Button(permission == .microphone && permissions.status(for: permission) == .pending ? "Allow" : "Open System Settings ↗") {
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
            VStack(alignment: .leading, spacing: 7) {
                Text("INPUT DEVICE")
                    .font(PersonalScribeTheme.Typography.sectionLabel.font)
                    .foregroundStyle(palette.secondaryText)
                HStack(spacing: PersonalScribeTheme.Spacing.sm) {
                    Image(systemName: "mic.fill")
                        .foregroundStyle(palette.secondaryText)
                    ZStack {
                        HStack {
                            Text(selectedMicrophoneName)
                                .foregroundStyle(palette.primaryTextBase)
                                .lineLimit(1)
                            Spacer()
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(palette.secondaryText)
                        }
                        Menu {
                            ForEach(microphone.devices) { device in
                                Button(device.name) {
                                    Task { await microphone.selectDevice(id: device.id) }
                                }
                            }
                        } label: {
                            Color.clear
                                .contentShape(Rectangle())
                        }
                        .menuStyle(.borderlessButton)
                        .menuIndicator(.hidden)
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .accessibilityLabel("Input device: \(selectedMicrophoneName)")
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, PersonalScribeTheme.Spacing.md)
                .frame(width: 380, height: 40)
                .setupCard(palette: palette)
            }
            VStack(alignment: .leading, spacing: PersonalScribeTheme.Spacing.md) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Say something…").font(PersonalScribeTheme.Typography.headline.font)
                        Text("Try: “Hello Ninimma, can you hear me?”")
                            .font(PersonalScribeTheme.Typography.caption.font)
                            .foregroundStyle(palette.secondaryText)
                    }
                    Spacer()
                    if microphone.level > 0.02 {
                        Label("Hearing you", systemImage: "circle.fill")
                            .font(PersonalScribeTheme.Typography.caption.font)
                            .foregroundStyle(PersonalScribeTheme.Status.success)
                    }
                }
                SineWaveView(
                    audioLevel: Double(microphone.level),
                    decayMode: .animated,
                    palette: .default,
                    onDarkBackground: colorScheme == .dark
                )
                    .frame(height: 28)
            }
            .padding(PersonalScribeTheme.Spacing.lg)
            .setupCard(palette: palette)
            Label("You can switch microphones any time from the Ninimma menu bar.", systemImage: "info.circle")
                .font(PersonalScribeTheme.Typography.caption.font)
                .foregroundStyle(palette.secondaryText)
        }
        .task { await microphone.appear() }
        .onDisappear { Task { await microphone.disappear() } }
    }

    private var modelStep: some View {
        VStack(alignment: .leading, spacing: PersonalScribeTheme.Spacing.md) {
            title("Your voice model", subtitle: "Ninimma is preparing the active on-device model for dictation.")
            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Image(systemName: "waveform")
                        .foregroundStyle(palette.brandChampagne)
                    Text(model.selectedModel.displayName)
                        .font(PersonalScribeTheme.Typography.body.font.weight(.semibold))
                    if model.selectedModel.id == model.recommendedModel.id {
                        Text("RECOMMENDED")
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .background(Capsule().fill(palette.secondaryText.opacity(0.15)))
                    }
                    Spacer()
                }
                Text(modelDetails(for: model.selectedModel))
                    .font(PersonalScribeTheme.Typography.caption.font)
                    .foregroundStyle(palette.secondaryText)
                modelProgress
            }
            .padding(PersonalScribeTheme.Spacing.md)
            .setupCard(palette: palette, highlighted: true)
            HStack(alignment: .firstTextBaseline) {
                Button("More models in Settings → AI Models") { model.showAllModels() }
                    .buttonStyle(.link)
                Spacer()
                Text("Download continues if you move on")
                    .font(PersonalScribeTheme.Typography.caption.font)
                    .foregroundStyle(palette.secondaryText)
            }
        }
        .onAppear { model.appear() }
    }

    @ViewBuilder
    private var modelProgress: some View {
        if let state = model.selectedState {
            switch state.phase {
            case .downloading:
                VStack(alignment: .leading, spacing: 5) {
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(palette.secondaryText.opacity(0.16))
                            Capsule()
                                .fill(palette.brandChampagne)
                                .frame(width: proxy.size.width * state.fractionCompleted)
                        }
                    }
                    .frame(height: 4)
                    HStack {
                        Spacer()
                        Text(downloadProgressLabel(state))
                            .font(PersonalScribeTheme.Typography.caption.font)
                            .foregroundStyle(palette.secondaryText)
                    }
                }
            case .loading:
                ProgressView().controlSize(.small)
                Text("Preparing model…").font(PersonalScribeTheme.Typography.caption.font)
            case .ready:
                Label("Ready", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(PersonalScribeTheme.Status.success)
            case .notDownloaded:
                Text("Not downloaded").font(PersonalScribeTheme.Typography.caption.font)
            case .failed(let message):
                Text(message).font(PersonalScribeTheme.Typography.caption.font)
                    .foregroundStyle(PersonalScribeTheme.Status.error)
            }
        }
    }

    private var shortcutStep: some View {
        VStack(alignment: .leading, spacing: PersonalScribeTheme.Spacing.lg) {
            title("Try the shortcut", subtitle: "Tap once to start and again to stop. Hold to talk, release to transcribe.")
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 9) {
                    ForEach(Array(hotkeyKeycaps.enumerated()), id: \.offset) { index, label in
                        if index > 0 {
                            Text("+")
                                .foregroundStyle(palette.secondaryText)
                        }
                        Text(label)
                            .font(.system(size: 14, weight: .semibold))
                            .frame(minWidth: 46, minHeight: 46)
                            .padding(.horizontal, 8)
                            .setupCard(palette: palette)
                    }
                }
                Button("Change in Settings → Shortcuts") { onOpenShortcuts() }
                    .buttonStyle(.link)
            }
            if model.isReady {
                VStack(alignment: .leading, spacing: 7) {
                    Text("PRACTICE HERE")
                        .font(PersonalScribeTheme.Typography.sectionLabel.font)
                        .foregroundStyle(palette.secondaryText)
                    ZStack(alignment: .topLeading) {
                        if flow.practiceText.isEmpty {
                            Text("Use \(hotkeyKeycaps.joined(separator: " + ")) and say “Hello Ninimma, this is my first dictation.”")
                                .font(PersonalScribeTheme.Typography.body.font)
                                .foregroundStyle(palette.secondaryText)
                                .padding(14)
                                .allowsHitTesting(false)
                        }
                        SetupPracticeTextEditor(
                            text: Binding(
                                get: { flow.practiceText },
                                set: { flow.updatePracticeText($0) }
                            ),
                            onPaste: { flow.recordPracticePaste($0) }
                        )
                        .padding(8)
                    }
                    .frame(height: 100)
                    .background(
                        RoundedRectangle(cornerRadius: PersonalScribeTheme.Radius.md, style: .continuous)
                            .fill(Color.clear)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: PersonalScribeTheme.Radius.md, style: .continuous)
                            .strokeBorder(palette.secondaryText.opacity(0.35), lineWidth: 1)
                    )
                }
                .onAppear {
                    if flow.practiceText.isEmpty && flow.practiceResult == nil {
                        flow.beginPractice()
                    }
                }
                .onChange(of: microphone.practiceSessionEvent) { _, event in
                    if let event {
                        flow.recordPracticeSessionEvent(event)
                    }
                }
                .onAppear { Task { await microphone.setPracticeVisible(true) } }
                .onDisappear {
                    flow.disarmPracticePaste()
                    Task { await microphone.setPracticeVisible(false) }
                }
                if microphone.isRecording {
                    HStack(spacing: PersonalScribeTheme.Spacing.sm) {
                        Label("Recording · \(formattedElapsed)", systemImage: "circle.fill")
                            .foregroundStyle(PersonalScribeTheme.Status.error)
                        Text("Press \(hotkeyKeycaps.joined(separator: " + ")) again to stop and paste")
                            .foregroundStyle(palette.secondaryText)
                    }
                    .font(PersonalScribeTheme.Typography.caption.font.weight(.semibold))
                }
                if let result = flow.practiceResult {
                    HStack {
                        Label("It worked · \(result.wordCount) words pasted in \(result.elapsedSeconds, specifier: "%.1f") s", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(PersonalScribeTheme.Status.success)
                        Spacer()
                        Button("Try again") { flow.tryPracticeAgain() }
                            .buttonStyle(.plain)
                            .padding(.horizontal, 13)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(PersonalScribeTheme.Status.success.opacity(0.12)))
                    }
                    .frame(minHeight: 54)
                    .padding(.horizontal, PersonalScribeTheme.Spacing.md)
                    .background(
                        RoundedRectangle(cornerRadius: PersonalScribeTheme.Radius.md, style: .continuous)
                            .fill(PersonalScribeTheme.Status.success.opacity(0.07))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: PersonalScribeTheme.Radius.md, style: .continuous)
                            .strokeBorder(PersonalScribeTheme.Status.success.opacity(0.8), lineWidth: 1)
                    )
                }
            } else {
                Label("Waiting for the voice model to finish downloading", systemImage: "clock")
                    .foregroundStyle(palette.secondaryText)
                    .padding(PersonalScribeTheme.Spacing.lg)
                    .setupCard(palette: palette)
            }
        }
    }

    private var practicePillPreview: some View {
        VStack(alignment: .center, spacing: 6) {
            Text("Pill appears at the bottom of your screen")
                .font(PersonalScribeTheme.Typography.caption.font)
                .foregroundStyle(palette.secondaryText)
            PillOverlayView(model: pillPreview)
                .frame(width: 220, height: 36)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .onAppear { updatePillPreviewLevel() }
        .onChange(of: microphone.isRecording) { _, _ in updatePillPreviewLevel() }
        .onChange(of: microphone.level) { _, _ in updatePillPreviewLevel() }
    }

    private func updatePillPreviewLevel() {
        pillPreview.audioLevel = microphone.isRecording ? Double(microphone.level) : 0
    }

    private var footer: some View {
        HStack {
            ActionButton(title: "Skip setup", variant: .secondary) {
                flow.skip(satisfaction: currentSatisfaction)
                onClose()
            }
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

    private var hotkeyKeycaps: [String] {
        HotkeyShortcutFormatter.onboardingKeycaps(for: checklist.recordingHotkey)
    }

    private var formattedElapsed: String {
        let seconds = microphone.recordingElapsedSeconds
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    private func permissionStatusColor(_ permission: Permission) -> Color {
        permissions.status(for: permission) == .granted
            ? PersonalScribeTheme.Status.success
            : PersonalScribeTheme.Status.warning
    }

    private func permissionStatusLabel(_ permission: Permission) -> String {
        if permission == .accessibility,
           permissions.status(for: permission) != .granted {
            return "Optional"
        }
        return permissions.statusLabel(for: permission)
    }

    private var selectedMicrophoneName: String {
        microphone.devices.first { $0.id == microphone.selectedDeviceID }?.name
            ?? "System default"
    }

    private func modelDetails(for descriptor: ModelDescriptor) -> String {
        let size = ByteCountFormatter.string(
            fromByteCount: descriptor.approximateSizeBytes,
            countStyle: .file
        )
        return "\(descriptor.shortDescription) · \(size) · \(descriptor.worksWith ?? "Auto language")"
    }

    private func downloadProgressLabel(_ state: ModelDownloadState) -> String {
        let total = model.selectedModel.approximateSizeBytes
        let received = Int64(Double(total) * state.fractionCompleted)
        let receivedLabel = ByteCountFormatter.string(fromByteCount: received, countStyle: .file)
        let totalLabel = ByteCountFormatter.string(fromByteCount: total, countStyle: .file)
        return "Downloading · \(receivedLabel) of \(totalLabel) · \(Int(state.fractionCompleted * 100))%"
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

@MainActor
private struct SetupMicrophoneObserver<Content: View>: View {
    @ObservedObject var microphone: SetupMicrophoneViewModel
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
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

private struct SetupPracticeTextEditor: NSViewRepresentable {
    @Binding var text: String
    let onPaste: @MainActor (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onPaste: onPaste)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .noBorder

        let textView = PasteAwareTextView()
        textView.delegate = context.coordinator
        textView.onPaste = context.coordinator.onPaste
        textView.isEditable = true
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.font = NSFont.preferredFont(forTextStyle: .body)
        textView.textContainerInset = NSSize(width: 4, height: 5)
        textView.string = text
        scrollView.documentView = textView
        DispatchQueue.main.async { [weak textView] in
            guard let textView else { return }
            textView.window?.makeFirstResponder(textView)
        }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? PasteAwareTextView else { return }
        context.coordinator.onPaste = onPaste
        textView.onPaste = context.coordinator.onPaste
        if textView.string != text {
            textView.string = text
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var text: String
        var onPaste: @MainActor (String) -> Void

        init(text: Binding<String>, onPaste: @escaping @MainActor (String) -> Void) {
            _text = text
            self.onPaste = onPaste
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text = textView.string
        }
    }
}

@MainActor
private final class PasteAwareTextView: NSTextView {
    var onPaste: (@MainActor (String) -> Void)?

    override func paste(_ sender: Any?) {
        let pastedText = NSPasteboard.general.string(forType: .string) ?? ""
        super.paste(sender)
        onPaste?(pastedText)
    }
}
