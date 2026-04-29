import SwiftUI
import UniformTypeIdentifiers
import PersonalScribeCore
import PersonalScribeSession

@MainActor
struct ModesListView: View {
    @ObservedObject var viewModel: ModesListViewModel
    @State private var showPresetPicker = false
    @State private var detailPath: [String] = []
    @State private var draggedModeID: String? = nil
    @State private var dragBaseModeIDs: [String] = []
    @State private var previewModeIDs: [String]? = nil
    @State private var isListDropTargeted = false
    @Environment(\.colorScheme) private var colorScheme

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
        .onChange(of: isListDropTargeted) { _, isTargeted in
            if !isTargeted, draggedModeID != nil {
                cancelDragPreview()
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
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(displayedModes, id: \.id) { mode in
                    VStack(spacing: 0) {
                        draggableModeRow(for: mode)

                        if mode.id != displayedModes.last?.id {
                            Divider()
                                .padding(.leading, PersonalScribeTheme.Spacing.md)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.clear)
        // Track whether the drag is still inside the list so a
        // cancelled / abandoned drag doesn't leave the preview order
        // stuck on screen.
        .onDrop(of: [UTType.plainText], isTargeted: $isListDropTargeted) { _, _ in
            false
        }
    }

    private var displayedModes: [WorkflowMode] {
        guard let previewModeIDs else {
            return viewModel.customModes
        }

        let modesByID = Dictionary(uniqueKeysWithValues: viewModel.customModes.map { ($0.id, $0) })
        let reordered = previewModeIDs.compactMap { modesByID[$0] }
        guard reordered.count == viewModel.customModes.count else {
            return viewModel.customModes
        }
        return reordered
    }

    private var rowDragHighlight: Color {
        PersonalScribeTheme.Palette.for(scheme: colorScheme)
            .hoverState
            .opacity(0.45)
    }

    private func draggableModeRow(for mode: WorkflowMode) -> some View {
        let isDragged = draggedModeID == mode.id

        return ModeRowView(
            mode: mode,
            isCurrent: viewModel.currentModeID == mode.id,
            isDefault: viewModel.defaultModeID == mode.id,
            validity: viewModel.validityByID[mode.id] ?? .valid,
            onTapBody: { detailPath.append(mode.id) },
            onTapStar: { viewModel.setDefault(mode) }
        )
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(
                cornerRadius: PersonalScribeTheme.Radius.row,
                style: .continuous
            )
            .fill(isDragged ? rowDragHighlight : .clear)
        }
        .opacity(isDragged ? 0.95 : 1.0)
        .onDrag {
            beginDrag(modeID: mode.id)
            return NSItemProvider(object: NSString(string: mode.id))
        }
        .onDrop(
            of: [UTType.plainText],
            delegate: ModeRowDropDelegate(
                targetID: mode.id,
                resolveDraggedModeID: { draggedModeID },
                updatePreview: updatePreview(dragging:over:),
                commit: commitDragPreview
            )
        )
    }

    private func beginDrag(modeID: String) {
        draggedModeID = modeID
        dragBaseModeIDs = viewModel.customModes.map(\.id)
        previewModeIDs = dragBaseModeIDs
    }

    private func updatePreview(dragging draggedID: String, over targetID: String) {
        let currentIDs = previewModeIDs ?? dragBaseModeIDs
        let updated = ModesListReorder.previewIDs(
            dragging: draggedID,
            over: targetID,
            in: currentIDs
        )
        if updated != previewModeIDs {
            previewModeIDs = updated
        }
    }

    private func commitDragPreview() {
        defer { cancelDragPreview() }

        guard let draggedModeID, let previewModeIDs else {
            return
        }
        guard let move = ModesListReorder.commitMove(
            dragging: draggedModeID,
            from: dragBaseModeIDs,
            to: previewModeIDs
        ) else {
            return
        }
        viewModel.reorder(from: move.source, to: move.destination)
    }

    private func cancelDragPreview() {
        draggedModeID = nil
        dragBaseModeIDs = []
        previewModeIDs = nil
    }
}

struct ModesListReorder {
    static func previewIDs(
        dragging draggedID: String,
        over targetID: String,
        in ids: [String]
    ) -> [String] {
        guard
            let sourceIndex = ids.firstIndex(of: draggedID),
            let targetIndex = ids.firstIndex(of: targetID),
            sourceIndex != targetIndex
        else {
            return ids
        }

        var updated = ids
        let movedID = updated.remove(at: sourceIndex)
        updated.insert(movedID, at: targetIndex)
        return updated
    }

    static func commitMove(
        dragging draggedID: String,
        from originalIDs: [String],
        to previewIDs: [String]
    ) -> (source: IndexSet, destination: Int)? {
        guard originalIDs != previewIDs else {
            return nil
        }
        guard
            let sourceIndex = originalIDs.firstIndex(of: draggedID),
            let targetIndex = previewIDs.firstIndex(of: draggedID)
        else {
            return nil
        }

        let destination = targetIndex > sourceIndex ? targetIndex + 1 : targetIndex
        return (source: IndexSet(integer: sourceIndex), destination: destination)
    }
}

private struct ModeRowDropDelegate: DropDelegate {
    let targetID: String
    let resolveDraggedModeID: () -> String?
    let updatePreview: (String, String) -> Void
    let commit: () -> Void

    func validateDrop(info: DropInfo) -> Bool {
        resolveDraggedModeID() != nil
    }

    func dropEntered(info: DropInfo) {
        guard let draggedModeID = resolveDraggedModeID() else {
            return
        }
        guard draggedModeID != targetID else {
            return
        }
        updatePreview(draggedModeID, targetID)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        commit()
        return true
    }
}
