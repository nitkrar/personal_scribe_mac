import SwiftUI
import PersonalScribeCore
import PersonalScribeSession

@MainActor
struct ModeDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: ModeDetailViewModel
    @ObservedObject private var modelService: ActiveModelService
    @State private var nameDraft: String
    @State private var isEditingName = false
    @State private var hotkeySheetPresented = false
    @State private var activeAlert: DetailAlert?

    init(
        mode: WorkflowMode,
        registry: WorkflowModeRegistry,
        modelService: ActiveModelService
    ) {
        _viewModel = StateObject(
            wrappedValue: ModeDetailViewModel(
                mode: mode,
                registry: registry,
                registeredDescriptors: modelService.registeredModels
            )
        )
        self.modelService = modelService
        _nameDraft = State(initialValue: mode.name)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PersonalScribeTheme.Spacing.lg) {
                titleHeader
                pipelineCard
                voiceModelCard
                processorsCard
                captureCard
                outputCard
                hotkeyCard
                deleteCard
            }
            .padding(PersonalScribeTheme.Spacing.windowPadding)
        }
        .navigationTitle(viewModel.mode.name)
        .toolbar {
            // macOS NavigationStack doesn't auto-render a back chevron
            // the way iOS does; an explicit toolbar button is needed.
            // MV-MODES-3 already assumes "Tap the back arrow" works.
            ToolbarItem(placement: .navigation) {
                Button {
                    dismiss()
                } label: {
                    Label("Back to Modes", systemImage: "chevron.left")
                }
                .help("Back to Modes")
            }
        }
        .alert(item: $activeAlert) { alert in
            switch alert {
            case .confirmDelete:
                Alert(
                    title: Text("Delete \"\(viewModel.mode.name)\"?"),
                    message: Text("This removes the mode permanently. The recipe is not recoverable."),
                    primaryButton: .destructive(Text("Delete")) {
                        confirmDelete()
                    },
                    secondaryButton: .cancel()
                )
            case .deleteFailed(let message):
                Alert(
                    title: Text("Couldn't delete mode"),
                    message: Text(message),
                    dismissButton: .default(Text("OK"))
                )
            }
        }
    }

    private var titleHeader: some View {
        HStack(spacing: PersonalScribeTheme.Spacing.md) {
            Image(systemName: viewModel.mode.glyph)
                .font(.system(size: 20, weight: .medium))
                .frame(width: 28, height: 28)
            if isEditingName {
                TextField("Mode name", text: $nameDraft, onCommit: commitName)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(commitName)
                    .frame(maxWidth: 320)
            } else {
                Text(viewModel.mode.name)
                    .font(PersonalScribeTheme.Typography.largeTitle.font)
                    .onTapGesture {
                        nameDraft = viewModel.mode.name
                        isEditingName = true
                    }
            }
            Spacer(minLength: 0)
        }
    }

    private func commitName() {
        viewModel.setName(nameDraft)
        isEditingName = false
    }

    private var pipelineCard: some View {
        SettingsCard {
            Toggle(isOn: realtimeBinding) {
                VStack(alignment: .leading) {
                    Text("Realtime").font(PersonalScribeTheme.Typography.body.font.weight(.medium))
                    Text("Show a live on-screen transcript as you speak.")
                        .font(PersonalScribeTheme.Typography.caption.font)
                        .foregroundStyle(.secondary)
                }
            }

            if viewModel.realtimeOn {
                Divider()
                VStack(spacing: PersonalScribeTheme.Spacing.sm) {
                    ParameterPickerView(
                        title: "Live transcript card",
                        settingKey: PreferenceKeys.streamingLiveCardEnabled,
                        parameter: viewModel.liveTranscriptCardParameter,
                        onChange: { viewModel.setLiveTranscriptCard($0) }
                    )
                    Divider()
                    ParameterPickerView(
                        title: "Live cursor streaming",
                        settingKey: PreferenceKeys.streamingLiveCursorEnabled,
                        parameter: viewModel.liveCursorStreamingParameter,
                        onChange: { viewModel.setLiveCursorStreaming($0) }
                    )
                    Text("Appends each end-of-utterance chunk into the focused text field while recording. Requires Accessibility access.")
                        .font(PersonalScribeTheme.Typography.caption.font)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Divider()
                    ParameterPickerView(
                        title: "Authoritative second pass",
                        settingKey: PreferenceKeys.streamingSecondPassEnabled,
                        parameter: viewModel.authoritativeSecondPassParameter,
                        onChange: { viewModel.setAuthoritativeSecondPass($0) }
                    )
                }
            }
        }
    }

    private var realtimeBinding: Binding<Bool> {
        Binding(
            get: { viewModel.realtimeOn },
            set: { viewModel.setRealtime($0) }
        )
    }

    private var voiceModelCard: some View {
        SettingsCard {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading) {
                    Text("Voice model").font(PersonalScribeTheme.Typography.body.font.weight(.medium))
                    Text(voiceModelCaption)
                        .font(PersonalScribeTheme.Typography.caption.font)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: PersonalScribeTheme.Spacing.sm)
                voiceModelMenu
            }

            if !viewModel.languageOptions.isEmpty {
                Divider()
                ModeLanguagePickerView(
                    selectedLanguage: viewModel.selectedLanguage,
                    options: viewModel.languageOptions,
                    onChange: { viewModel.setLanguage($0) }
                )
            }
        }
    }

    /// Caption under the row title — always shows "Use globally active"
    /// vs. "Pinned to <Name>" so the picker's button label and the
    /// caption together communicate the mode's choice unambiguously.
    private var voiceModelCaption: String {
        if let pinID = viewModel.voiceModelPinID,
           let pinned = modelService.registeredModels.first(where: { $0.id == pinID }) {
            return "Pinned to \(pinned.displayName)"
        }
        if viewModel.voiceModelPinID != nil {
            // Pin references a descriptor we no longer know about
            // (catalog removed it). Validity check elsewhere flags
            // the mode; the row just surfaces the broken state.
            return "Pinned model unavailable"
        }
        return "Use globally active (\(activeVoiceModelDisplayName))"
    }

    /// SwiftUI Menu that drives the per-mode pin. First item resets to
    /// "use globally active" (nil pin); subsequent items pin to a
    /// specific descriptor. Filters to descriptors of the mode's
    /// transcriber kind, respecting `enabledModels` so users can't
    /// pick a flag-disabled model.
    private var voiceModelMenu: some View {
        Menu {
            Button {
                viewModel.setVoiceModelPin(nil)
            } label: {
                voiceModelMenuItemLabel(
                    title: "Use globally active",
                    detail: activeVoiceModelDisplayName,
                    selected: viewModel.voiceModelPinID == nil
                )
            }
            Divider()
            ForEach(pickableDescriptors, id: \.id) { descriptor in
                Button {
                    viewModel.setVoiceModelPin(descriptor.id)
                } label: {
                    voiceModelMenuItemLabel(
                        title: descriptor.displayName,
                        detail: nil,
                        selected: viewModel.voiceModelPinID == descriptor.id
                    )
                }
            }
        } label: {
            Text(voiceModelMenuButtonLabel)
                .font(PersonalScribeTheme.Typography.body.font)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private func voiceModelMenuItemLabel(
        title: String,
        detail: String?,
        selected: Bool
    ) -> some View {
        HStack {
            if selected {
                Image(systemName: "checkmark")
            }
            if let detail {
                Text("\(title) (\(detail))")
            } else {
                Text(title)
            }
        }
    }

    /// Button label = the picker's current selection. Same logic as the
    /// caption inverted: pinned shows the model name; unpinned shows
    /// "Globally active".
    private var voiceModelMenuButtonLabel: String {
        Self.resolvedVoiceModelMenuButtonLabel(
            pinID: viewModel.voiceModelPinID,
            modelService: modelService
        )
    }

    private var pickableDescriptors: [ModelDescriptor] {
        let kind: ModelKind = viewModel.realtimeOn ? .streamingASR : .asr
        return Self.pickableDescriptorsForKind(kind, modelService: modelService)
    }

    private var activeVoiceModelDisplayName: String {
        let kind: ModelKind = viewModel.realtimeOn ? .streamingASR : .asr
        return modelService.activeDescriptor(for: kind)?.displayName ?? "—"
    }

    private var processorsCard: some View {
        SettingsCard {
            Toggle(isOn: diarizationBinding) {
                VStack(alignment: .leading) {
                    Text("Identify speakers")
                        .font(PersonalScribeTheme.Typography.body.font.weight(.medium))
                    Text("Splits transcripts into per-speaker turns.")
                        .font(PersonalScribeTheme.Typography.caption.font)
                        .foregroundStyle(.secondary)
                }
            }
            .disabled(viewModel.realtimeOn) // streaming + diarization unsupported V1

            // Per-mode override only surfaces when the mode actually
            // has a diarized processor — otherwise there's nothing for
            // the picker to override against. The view-model returns
            // nil in that case.
            if let sensitivityParameter = viewModel.sensitivityParameter {
                Divider()
                SensitivityParameterPickerView(
                    title: "Speaker separation sensitivity",
                    parameter: sensitivityParameter,
                    onChange: { viewModel.setSpeakerSeparationSensitivity($0) }
                )
            }
        }
    }

    static func resolvedVoiceModelMenuButtonLabel(
        pinID: String?,
        modelService: ActiveModelService
    ) -> String {
        if let pinID {
            if let pinned = modelService.registeredModels.first(where: { $0.id == pinID }) {
                return pinned.displayName
            }
            return "Unknown model"
        }
        return "Globally active"
    }

    static func pickableDescriptorsForKind(
        _ kind: ModelKind,
        modelService: ActiveModelService
    ) -> [ModelDescriptor] {
        modelService.visibleModels(kind: kind)
    }

    private var diarizationBinding: Binding<Bool> {
        Binding(
            get: { viewModel.diarizationOn },
            set: { viewModel.setDiarization($0) }
        )
    }

    private var captureCard: some View {
        SettingsCard {
            ParameterPickerView(
                title: "Auto-stop on silence",
                settingKey: PreferenceKeys.vadAutoStopEnabled,
                parameter: viewModel.autoStopParameter,
                onChange: { viewModel.setAutoStop($0) }
            )
        }
    }

    private var outputCard: some View {
        SettingsCard {
            VStack(spacing: PersonalScribeTheme.Spacing.sm) {
                ParameterPickerView(
                    title: "Auto-paste",
                    settingKey: PreferenceKeys.autoPasteEnabled,
                    parameter: viewModel.autoPasteParameter,
                    onChange: { viewModel.setAutoPaste($0) }
                )
                Divider()
                ParameterPickerView(
                    title: "Restore clipboard",
                    settingKey: PreferenceKeys.clipboardRestoreEnabled,
                    parameter: viewModel.restoreClipboardParameter,
                    onChange: { viewModel.setRestoreClipboard($0) }
                )
            }
        }
    }

    private var hotkeyCard: some View {
        SettingsCard {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading) {
                    Text("Per-mode hotkey")
                        .font(PersonalScribeTheme.Typography.body.font.weight(.medium))
                    Text(viewModel.mode.hotkey.map(HotkeyShortcutFormatter.displayString) ?? "None")
                        .font(PersonalScribeTheme.Typography.caption.font)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: PersonalScribeTheme.Spacing.sm)
                if viewModel.mode.hotkey != nil {
                    Button {
                        viewModel.setHotkey(nil)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.plain)
                    .help("Clear hotkey")
                }
                Button(viewModel.mode.hotkey == nil ? "Set hotkey" : "Change") {
                    hotkeySheetPresented = true
                }
            }
        }
        .sheet(isPresented: $hotkeySheetPresented) {
            HotkeyRecorder(
                currentPreference: viewModel.mode.hotkey ?? HotkeyPreference(keyCode: 0, tapCount: 1, modifiers: 0),
                onConfirm: { newPreference in
                    viewModel.setHotkey(newPreference)
                    hotkeySheetPresented = false
                },
                onCancel: { hotkeySheetPresented = false },
                additionalReservations: viewModel.siblingHotkeyReservations()
                    + [HotkeyPreference.resolve()]
            )
        }
    }

    private var deleteCard: some View {
        SettingsCard {
            Button(role: .destructive) {
                activeAlert = .confirmDelete
            } label: {
                HStack {
                    VStack(alignment: .leading) {
                        Text("Delete this mode")
                            .font(PersonalScribeTheme.Typography.body.font.weight(.medium))
                            .foregroundStyle(.red)
                        Text("Removes the recipe permanently.")
                            .font(PersonalScribeTheme.Typography.caption.font)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "trash")
                        .foregroundStyle(.red)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private func confirmDelete() {
        guard viewModel.delete() else {
            if let message = viewModel.lastError {
                activeAlert = .deleteFailed(message)
            }
            return
        }
        dismiss()
    }

    private enum DetailAlert: Identifiable {
        case confirmDelete
        case deleteFailed(String)

        var id: String {
            switch self {
            case .confirmDelete:
                return "confirm-delete"
            case .deleteFailed(let message):
                return "delete-failed-\(message)"
            }
        }
    }
}
