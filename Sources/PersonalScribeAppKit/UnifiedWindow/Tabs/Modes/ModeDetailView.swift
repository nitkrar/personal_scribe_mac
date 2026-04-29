import SwiftUI
import PersonalScribeCore
import PersonalScribeSession

@MainActor
struct ModeDetailView: View {
    @StateObject private var viewModel: ModeDetailViewModel
    @ObservedObject private var modelService: ActiveModelService
    @State private var nameDraft: String
    @State private var isEditingName = false
    @State private var hotkeySheetPresented = false
    let onRequestDelete: (WorkflowMode) -> Void

    init(
        mode: WorkflowMode,
        registry: WorkflowModeRegistry,
        modelService: ActiveModelService,
        onRequestDelete: @escaping (WorkflowMode) -> Void
    ) {
        _viewModel = StateObject(
            wrappedValue: ModeDetailViewModel(mode: mode, registry: registry)
        )
        self.modelService = modelService
        _nameDraft = State(initialValue: mode.name)
        self.onRequestDelete = onRequestDelete
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
                    Text("Stream partial results as you speak.")
                        .font(PersonalScribeTheme.Typography.caption.font)
                        .foregroundStyle(.secondary)
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
        if let pinID = viewModel.voiceModelPinID {
            if let pinned = modelService.registeredModels.first(where: { $0.id == pinID }) {
                return pinned.displayName
            }
            return "Unknown model"
        }
        return "Globally active"
    }

    private var pickableDescriptors: [ModelDescriptor] {
        let kind: ModelKind = viewModel.realtimeOn ? .streamingASR : .asr
        return modelService.enabledModels(kind: kind)
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
        }
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
                Button(role: .destructive) {
                    onRequestDelete(viewModel.mode)
                } label: {
                    Image(systemName: "trash")
                }
            }
        }
    }
}
