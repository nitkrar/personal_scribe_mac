import SwiftUI
import SeshatCore

struct NotesView: View {
    @ObservedObject private var viewModel: NotesViewModel
    @Environment(\.colorScheme) private var colorScheme

    init(viewModel: NotesViewModel) {
        self.viewModel = viewModel
    }

    var selectedEntry: TranscriptEntry? {
        viewModel.selectedEntry
    }

    var searchFieldPrompt: String {
        "Search history"
    }

    var searchFieldBinding: Binding<String> {
        Binding(
            get: { viewModel.searchQuery },
            set: { query in
                Task { @MainActor in
                    await viewModel.search(query: query)
                }
            }
        )
    }

    var sidebar: NotesSidebar {
        NotesSidebar(viewModel: viewModel)
    }

    var editor: NotesEditor {
        NotesEditor(selectedEntry: selectedEntry)
    }

    var contextPanel: NotesContextPanel {
        NotesContextPanel(selectedEntry: selectedEntry)
    }

    var body: some View {
        let palette = SeshatTheme.Palette.for(scheme: colorScheme)

        HSplitView {
            sidebarColumn
                .frame(
                    minWidth: Layout.sidebarMinWidth,
                    idealWidth: Layout.sidebarIdealWidth
                )

            editor
                .frame(
                    minWidth: Layout.editorMinWidth,
                    idealWidth: Layout.editorIdealWidth
                )

            contextPanel
                .frame(
                    minWidth: Layout.contextMinWidth,
                    idealWidth: Layout.contextIdealWidth,
                    maxWidth: Layout.contextMaxWidth
                )
        }
        .frame(
            minWidth: Layout.windowMinWidth,
            minHeight: Layout.windowMinHeight
        )
        .background(palette.appBackground)
    }

    private var sidebarColumn: some View {
        let palette = SeshatTheme.Palette.for(scheme: colorScheme)

        return VStack(alignment: .leading, spacing: Layout.columnSpacing) {
            TextField(searchFieldPrompt, text: searchFieldBinding)
                .textFieldStyle(.roundedBorder)

            sidebar
        }
        .padding(Layout.columnPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(palette.appBackground)
    }
}

private extension NotesView {
    enum Layout {
        static let windowMinWidth: CGFloat = 980
        static let windowMinHeight: CGFloat = 620
        static let sidebarMinWidth: CGFloat = 250
        static let sidebarIdealWidth: CGFloat = 300
        static let editorMinWidth: CGFloat = 420
        static let editorIdealWidth: CGFloat = 540
        static let contextMinWidth: CGFloat = 220
        static let contextIdealWidth: CGFloat = 260
        static let contextMaxWidth: CGFloat = 320
        static let columnPadding: CGFloat = 16
        static let columnSpacing: CGFloat = 12
    }
}
