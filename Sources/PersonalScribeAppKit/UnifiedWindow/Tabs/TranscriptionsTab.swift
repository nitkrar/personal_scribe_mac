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
///   or explicit uppercased "APRIL 17, 2026" for older entries — with
///   `TranscriptRow` rendering each entry (timestamp + 2-line truncated
///   preview).
///
/// Not yet wired into `UnifiedWindowView`; main session wires it in a
/// follow-up commit.
@MainActor
struct TranscriptionsTab: View {
    @ObservedObject private var viewModel: TranscriptionsTabViewModel
    @Environment(\.colorScheme) private var colorScheme

    init(viewModel: TranscriptionsTabViewModel) {
        self.viewModel = viewModel
    }

    var body: some View {
        let palette = PersonalScribeTheme.Palette.for(scheme: colorScheme)

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
                                TranscriptRow(
                                    title: HomeTab.title(for: entry),
                                    timestamp: entry.timestamp,
                                    preview: entry.text,
                                    referenceDate: now
                                )
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
        .task {
            await viewModel.load()
        }
    }
}
