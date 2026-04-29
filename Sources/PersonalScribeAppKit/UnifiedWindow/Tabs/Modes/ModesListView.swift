import SwiftUI
import PersonalScribeCore
import PersonalScribeSession

@MainActor
struct ModesListView: View {
    @ObservedObject var viewModel: ModesListViewModel
    @State private var showPresetPicker = false
    @State private var pendingDelete: WorkflowMode? = nil
    @State private var detailPath: [String] = []

    private let modelService: ActiveModelService
    private let registry: WorkflowModeRegistry

    init(
        viewModel: ModesListViewModel,
        modelService: ActiveModelService = AppComposition.modelService,
        registry: WorkflowModeRegistry = AppComposition.workflowModeRegistry
    ) {
        self.viewModel = viewModel
        self.modelService = modelService
        self.registry = registry
    }

    var body: some View {
        NavigationStack(path: $detailPath) {
            content
                .navigationDestination(for: String.self) { modeID in
                    if let mode = viewModel.customModes.first(where: { $0.id == modeID }) {
                        ModeDetailView(
                            mode: mode,
                            registry: registry,
                            modelService: modelService,
                            onRequestDelete: { delete in
                                pendingDelete = delete
                            }
                        )
                    } else {
                        // Mode disappeared (deleted by another path);
                        // empty placeholder pops the user back.
                        Color.clear.onAppear { detailPath.removeAll() }
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            showPresetPicker = true
                        } label: {
                            Label("Add mode", systemImage: "plus")
                        }
                        .popover(isPresented: $showPresetPicker, arrowEdge: .bottom) {
                            PresetPickerPopover { preset in
                                if let created = viewModel.create(preset: preset) {
                                    detailPath = [created.id]
                                }
                                showPresetPicker = false
                            }
                            .frame(minWidth: 320)
                        }
                    }
                }
                .alert(item: deleteAlertItem) { item in
                    Alert(
                        title: Text("Delete \"\(item.mode.name)\"?"),
                        message: Text("This removes the mode permanently. The recipe is not recoverable."),
                        primaryButton: .destructive(Text("Delete")) {
                            viewModel.delete(item.mode)
                            // Pop back to the list if the deleted mode
                            // was the current detail target.
                            if detailPath.last == item.mode.id {
                                detailPath.removeAll()
                            }
                        },
                        secondaryButton: .cancel {
                            pendingDelete = nil
                        }
                    )
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.customModes.isEmpty {
            emptyState
        } else {
            modesList
        }
    }

    private var emptyState: some View {
        VStack(spacing: PersonalScribeTheme.Spacing.md) {
            Image(systemName: "rectangle.stack.badge.plus")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(.secondary)
            Text("No modes yet.")
                .font(PersonalScribeTheme.Typography.title.font)
            Text("Tap + to create one.")
                .font(PersonalScribeTheme.Typography.body.font)
                .foregroundStyle(.secondary)
            Button {
                showPresetPicker = true
            } label: {
                Label("Create your first mode", systemImage: "plus.circle.fill")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(PersonalScribeTheme.Spacing.windowPadding)
    }

    private var modesList: some View {
        // ScrollView + LazyVStack rather than List so single-row layouts
        // don't render as inset cards (macOS List's default chrome).
        // Drag-reorder is deferred to a follow-up — the user-visible
        // list ordering is set via array order in the registry, and
        // the `reorder` method on the view-model still works for any
        // future reorder UI.
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(viewModel.customModes.enumerated()), id: \.element.id) { index, mode in
                    ModeRowView(
                        mode: mode,
                        isCurrent: viewModel.currentModeID == mode.id,
                        isDefault: viewModel.defaultModeID == mode.id,
                        validity: viewModel.validityByID[mode.id] ?? .valid,
                        onTapBody: { detailPath.append(mode.id) },
                        onTapStar: { viewModel.setDefault(mode) }
                    )
                    if index < viewModel.customModes.count - 1 {
                        Divider().padding(.leading, PersonalScribeTheme.Spacing.md)
                    }
                }
            }
        }
    }

    private var deleteAlertItem: Binding<DeletePromptItem?> {
        Binding(
            get: {
                pendingDelete.map { DeletePromptItem(mode: $0) }
            },
            set: { newValue in
                pendingDelete = newValue?.mode
            }
        )
    }

    private struct DeletePromptItem: Identifiable {
        let mode: WorkflowMode
        var id: String { mode.id }
    }
}
