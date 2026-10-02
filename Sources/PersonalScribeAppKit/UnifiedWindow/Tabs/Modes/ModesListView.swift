import SwiftUI
import PersonalScribeCore
import PersonalScribeSession

@MainActor
struct ModesListView: View {
    @ObservedObject var viewModel: ModesListViewModel
    @State private var showPresetPicker = false
    @State private var detailPath: [String] = []
    @State private var pendingDelete: WorkflowMode? = nil
    @State private var selectedModeID: String? = nil

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
                            modelService: modelService
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
        }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.customModes.isEmpty {
            emptyState
        } else {
            VStack(alignment: .leading, spacing: PersonalScribeTheme.Spacing.sm) {
                Text("Two-finger swipe or right-click a mode for options. Double-click to open. Drag to reorder the menu bar list.")
                    .font(PersonalScribeTheme.Typography.caption.font)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, PersonalScribeTheme.Spacing.md)
                modesList
            }
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

    /// Native `List` so macOS supplies drag-to-reorder (`.onMove`),
    /// trackpad swipe actions, and the context menu. Order only drives
    /// the menu bar's mode submenu; the star picks the hotkey's default.
    /// Rows carry no gestures (they block drag/swipe); single click
    /// selects, double-click / Return opens via the primary action.
    private var modesList: some View {
        List(selection: $selectedModeID) {
            ForEach(viewModel.customModes, id: \.id) { mode in
                ModeRowView(
                    mode: mode,
                    isCurrent: viewModel.currentModeID == mode.id,
                    isDefault: viewModel.defaultModeID == mode.id,
                    validity: viewModel.validityByID[mode.id] ?? .valid,
                    onTapBody: { detailPath.append(mode.id) },
                    onTapStar: { viewModel.setDefault(mode) }
                )
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        pendingDelete = mode
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
                .listRowBackground(Color.clear)
                .tag(mode.id)
            }
            .onMove { source, destination in
                viewModel.reorder(from: source, to: destination)
            }
        }
        .contextMenu(forSelectionType: String.self) { ids in
            if let mode = mode(for: ids) {
                Button("Open") { detailPath.append(mode.id) }
                Button("Set as Default") { viewModel.setDefault(mode) }
                    .disabled(viewModel.defaultModeID == mode.id)
                Divider()
                Button("Delete…", role: .destructive) { pendingDelete = mode }
            }
        } primaryAction: { ids in
            if let mode = mode(for: ids) {
                detailPath.append(mode.id)
            }
        }
        .listStyle(.plain)
        // Let the window tint show through, matching the other tabs
        // (the default List background drew a white card).
        .scrollContentBackground(.hidden)
        .confirmationDialog(
            "Delete \"\(pendingDelete?.name ?? "")\"?",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            presenting: pendingDelete
        ) { mode in
            Button("Delete", role: .destructive) { viewModel.delete(mode) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("This can't be undone.")
        }
    }

    private func mode(for ids: Set<String>) -> WorkflowMode? {
        guard let id = ids.first else { return nil }
        return viewModel.customModes.first { $0.id == id }
    }
}
