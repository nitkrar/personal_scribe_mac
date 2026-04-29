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
                    Text(activeVoiceModelDescription)
                        .font(PersonalScribeTheme.Typography.caption.font)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: PersonalScribeTheme.Spacing.sm)
                // #090 picks up per-mode override; for now the row is
                // read-only and points the user at AI Models.
                Text("Manage in AI Models tab")
                    .font(PersonalScribeTheme.Typography.caption.font)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var activeVoiceModelDescription: String {
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
