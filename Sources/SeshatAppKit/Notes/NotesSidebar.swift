import SwiftUI
import SeshatCore

struct NotesSidebar: View {
    struct RowModel: Identifiable, Equatable {
        let id: UUID
        let title: String
        let timestamp: Date
        let preview: String
        let isSelected: Bool
    }

    @ObservedObject private var viewModel: NotesViewModel
    @Environment(\.colorScheme) private var colorScheme

    init(viewModel: NotesViewModel) {
        self.viewModel = viewModel
    }

    var rowModels: [RowModel] {
        viewModel.entries.map { entry in
            RowModel(
                id: entry.id,
                title: title(for: entry.text),
                timestamp: entry.timestamp,
                preview: preview(for: entry.text),
                isSelected: entry.id == viewModel.selectedEntryID
            )
        }
    }

    var selection: Binding<UUID?> {
        Binding(
            get: { viewModel.selectedEntryID },
            set: { viewModel.select(id: $0) }
        )
    }

    var body: some View {
        let palette = SeshatTheme.Palette.for(scheme: colorScheme)

        List(selection: selection) {
            if rowModels.isEmpty {
                Text("No transcripts yet")
                    .font(SeshatTheme.Typography.body.font)
                    .foregroundStyle(palette.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, SeshatTheme.Spacing.rowPadding)
                    .listRowBackground(palette.appBackground)
            } else {
                ForEach(rowModels) { row in
                    TranscriptRow(
                        title: row.title,
                        timestamp: row.timestamp,
                        preview: row.preview,
                        isSelected: row.isSelected
                    )
                    .tag(row.id as UUID?)
                    .listRowInsets(
                        EdgeInsets(
                            top: Layout.rowInset,
                            leading: Layout.rowInset,
                            bottom: Layout.rowInset,
                            trailing: Layout.rowInset
                        )
                    )
                    .listRowBackground(palette.appBackground)
                }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(palette.appBackground)
    }

    private func title(for text: String) -> String {
        let lines = significantLines(in: text)
        if let firstLine = lines.first {
            return firstLine
        }

        let collapsed = TranscriptRow.Formatters.collapseWhitespace(text)
        return collapsed.isEmpty ? "Untitled Transcript" : collapsed
    }

    private func preview(for text: String) -> String {
        let lines = significantLines(in: text)
        if lines.count > 1 {
            return lines.dropFirst().joined(separator: " ")
        }

        return TranscriptRow.Formatters.collapseWhitespace(text)
    }

    private func significantLines(in text: String) -> [String] {
        text
            .components(separatedBy: .newlines)
            .map {
                TranscriptRow.Formatters.collapseWhitespace($0)
            }
            .filter { !$0.isEmpty }
    }
}

private extension NotesSidebar {
    enum Layout {
        static let rowInset: CGFloat = 4
    }
}
