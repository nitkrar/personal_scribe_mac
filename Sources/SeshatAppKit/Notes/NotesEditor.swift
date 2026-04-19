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
                // Read-only surface: `TextEditor.disabled(true)` suppresses
                // text selection on macOS, which defeats the purpose of a
                // history viewer (users can't copy their own transcripts
                // back out). Use selectable `Text` inside a `ScrollView`
                // instead — copy works, editing cannot happen, and the
                // Phase-3 "no edit persistence" design-lock still holds.
                ScrollView {
                    Text(displayText)
                        .font(SeshatTheme.Typography.body.font)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding(Layout.editorPadding)
                }
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
