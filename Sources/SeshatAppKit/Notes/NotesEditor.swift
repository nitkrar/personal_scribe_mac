import SwiftUI
import SeshatCore

struct NotesEditor: View {
    let selectedEntry: TranscriptEntry?

    @Environment(\.colorScheme) private var colorScheme

    var displayText: String {
        selectedEntry?.text ?? ""
    }

    var placeholderText: String {
        "Select a transcript to view its text."
    }

    var isShowingEmptyState: Bool {
        selectedEntry == nil
    }

    var body: some View {
        let palette = SeshatTheme.Palette.for(scheme: colorScheme)

        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: SeshatTheme.Radius.window, style: .continuous)
                .fill(palette.surface)

            if isShowingEmptyState {
                Text(placeholderText)
                    .font(SeshatTheme.Typography.body.font)
                    .foregroundStyle(palette.secondaryText)
                    .padding(Layout.contentPadding)
            } else {
                TextEditor(text: .constant(displayText))
                    .font(SeshatTheme.Typography.body.font)
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                    .disabled(true)
                    .opacity(1)
                    .padding(Layout.editorPadding)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: SeshatTheme.Radius.window, style: .continuous)
                .strokeBorder(
                    palette.brandChampagne.opacity(Layout.borderOpacity),
                    lineWidth: Layout.borderWidth
                )
        )
    }
}

private extension NotesEditor {
    enum Layout {
        static let contentPadding: CGFloat = 18
        static let editorPadding: CGFloat = 8
        static let borderWidth: CGFloat = 0.5
        static let borderOpacity: Double = 0.18
    }
}
