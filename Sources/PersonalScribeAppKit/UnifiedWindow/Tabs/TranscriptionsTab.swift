import PersonalScribeCore
import SwiftUI

/// Transcriptions tab of the unified window (M3.2).
///
/// Structure per `plans/App UI design/Claude_Final_Bundle_Prompt.md`
/// §3B:
///
/// * Hero header "Transcriptions" (`Typography.largeTitle`).
/// * Full-width search bar bound to `viewModel.searchText`.
/// * Scrollable list grouped by date bucket — "TODAY", "YESTERDAY",
///   or compact uppercased "APR 17" for older entries — with
///   `TranscriptRow` rendering each entry (timestamp + 2-line truncated
///   preview).
///
/// Not yet wired into `UnifiedWindowView`; main session wires it in a
/// follow-up commit.
@MainActor
struct TranscriptionsTab: View {
    @ObservedObject private var viewModel: TranscriptionsTabViewModel
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.windowTint) private var windowTint

    @State private var editingItem: TranscriptEditSheetItem?

    init(viewModel: TranscriptionsTabViewModel) {
        self.viewModel = viewModel
    }

    /// Resolve the tab-root background: prefer the injected
    /// `WindowTint.primaryBackground` when present (ensures warm / neutral
    /// / forced-dark surfaces paint through to the Transcriptions tab
    /// root), otherwise fall back to the palette's `appBackground` so
    /// previews and test harnesses still have an opaque surface rather
    /// than inheriting transparently from the ancestor. Mockup-gap A.5.
    static func resolvedBackground(
        windowTint: WindowTint?,
        palette: PersonalScribeTheme.Palette
    ) -> Color {
        if let tint = windowTint {
            return tint.primaryBackground
        }
        return palette.appBackground
    }

    var body: some View {
        let palette = PersonalScribeTheme.Palette.for(scheme: colorScheme)
        let background = Self.resolvedBackground(windowTint: windowTint, palette: palette)

        VStack(alignment: .leading, spacing: PersonalScribeTheme.Spacing.lg) {
            Text("Transcriptions")
                .font(PersonalScribeTheme.Typography.largeTitle.font)
                .foregroundStyle(palette.primaryText)

            // Use searchFieldStyle for a native macOS search bar
            // (magnifying glass icon, clear button, correct focus ring).
            TextField("Search transcriptions", text: $viewModel.searchText)
                .textFieldStyle(.plain)
                .padding(.vertical, 6)
                .padding(.horizontal, 10)
                .background {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(palette.surface)
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(palette.primaryText.opacity(0.1), lineWidth: 1)
                }
                .overlay(alignment: .leading) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(palette.secondaryText)
                        .padding(.leading, 10)
                        .allowsHitTesting(false)
                }
                .padding(.leading, 22)
                .frame(maxWidth: .infinity)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: PersonalScribeTheme.Spacing.md) {
                    let now = Date()
                    ForEach(viewModel.groupedByDate, id: \.bucket) { group in
                        Section {
                            ForEach(group.entries, id: \.id) { entry in
                                transcriptRow(entry: entry, referenceDate: now)
                            }
                        } header: {
                            Text(group.bucket)
                                .font(PersonalScribeTheme.Typography.sectionLabel.font)
                                .foregroundStyle(palette.secondaryText)
                                .padding(.top, PersonalScribeTheme.Spacing.sm)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(background)
        .task {
            await viewModel.load()
        }
        .sheet(item: $editingItem, content: editSheet)
    }

    @ViewBuilder
    private func transcriptRow(entry: TranscriptEntry, referenceDate: Date) -> some View {
        // Detail style — wall-clock time + 2-line preview; no separate title
        // surface. Trailing mode pill remains deferred until schema support
        // exists.
        TranscriptRow(
            timestamp: entry.timestamp,
            preview: entry.text,
            isSelected: editingItem?.entry.id == entry.id,
            onRetranscribe: retranscribeAction(for: entry),
            isRetranscribing: viewModel.isRetranscribing(entry),
            onDelete: deleteAction(for: entry.id),
            referenceDate: referenceDate
        )
        .contentShape(Rectangle())
        .onTapGesture {
            guard viewModel.canEdit else { return }
            editingItem = TranscriptEditSheetItem(entry: entry)
        }
    }

    private func deleteAction(for id: UUID) -> (() -> Void)? {
        guard viewModel.canDelete else {
            return nil
        }

        return {
            Task {
                try? await viewModel.delete(id: id)
            }
        }
    }

    private func retranscribeAction(for entry: TranscriptEntry) -> (() -> Void)? {
        guard viewModel.showsRetranscribeIcon(for: entry) else {
            return nil
        }

        return {
            Task {
                await viewModel.reTranscribe(entry)
            }
        }
    }

    @ViewBuilder
    private func editSheet(item: TranscriptEditSheetItem) -> some View {
        TranscriptEditSheet(
            entry: item.entry,
            onSave: { newText in
                try await viewModel.update(id: item.id, text: newText)
            }
        )
    }
}

/// Identifiable wrapper for `TranscriptEntry` so SwiftUI's `sheet(item:)` can
/// drive presentation without touching the Core module's struct conformance.
private struct TranscriptEditSheetItem: Identifiable {
    let entry: TranscriptEntry
    var id: UUID { entry.id }
}

/// Minimal edit sheet for a transcript body. No title field, no format
/// toolbar, no debounce — per #013 scope cut. Save on explicit button tap;
/// Cancel discards. Sheet dismissal via either button.
@MainActor
private struct TranscriptEditSheet: View {
    let entry: TranscriptEntry
    let onSave: @MainActor (String) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var draftText: String
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(entry: TranscriptEntry, onSave: @escaping @MainActor (String) async throws -> Void) {
        self.entry = entry
        self.onSave = onSave
        self._draftText = State(initialValue: entry.text)
    }

    var body: some View {
        let palette = PersonalScribeTheme.Palette.for(scheme: colorScheme)

        VStack(alignment: .leading, spacing: PersonalScribeTheme.Spacing.md) {
            Text("Edit transcript")
                .font(PersonalScribeTheme.Typography.title.font)
                .foregroundStyle(palette.primaryText)

            Text(entry.timestamp.formatted(.dateTime.month().day().hour().minute()))
                .font(PersonalScribeTheme.Typography.caption.font)
                .foregroundStyle(palette.secondaryText)

            TextEditor(text: $draftText)
                .font(PersonalScribeTheme.Typography.body.font)
                .foregroundStyle(palette.primaryText)
                .padding(8)
                .frame(minWidth: 420, minHeight: 240)
                .background {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(palette.surface)
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(palette.primaryText.opacity(0.1), lineWidth: 1)
                }

            if let errorMessage {
                Text(errorMessage)
                    .font(PersonalScribeTheme.Typography.caption.font)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                .disabled(isSaving)

                Button("Save") {
                    Task { @MainActor in
                        isSaving = true
                        errorMessage = nil
                        defer { isSaving = false }

                        do {
                            try await onSave(draftText)
                            dismiss()
                        } catch {
                            errorMessage = "Couldn’t save transcript edits."
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(isSaving || draftText == entry.text)
            }
        }
        .padding(PersonalScribeTheme.Spacing.lg)
        .frame(minWidth: 480, minHeight: 320)
        .background(palette.appBackground)
        .interactiveDismissDisabled(isSaving)
    }
}
