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
                                // Detail style — wall-clock time + 2-line
                                // preview; no separate title surface.
                                // TODO: mockup-gap — trailing mode pill
                                // deferred (TranscriptEntry has no mode
                                // field; requires schema + migration).
                                TranscriptRow(
                                    timestamp: entry.timestamp,
                                    preview: entry.text,
                                    onDelete: viewModel.canDelete ? {
                                        Task {
                                            try? await viewModel.delete(id: entry.id)
                                        }
                                    } : nil,
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
        .background(Self.resolvedBackground(windowTint: windowTint, palette: palette))
        .task {
            await viewModel.load()
        }
    }
}
