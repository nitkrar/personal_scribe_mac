import SwiftUI
import PersonalScribeCore

@MainActor
final class LiveDiagnosticsOverlayViewModel: ObservableObject {
    @Published fileprivate(set) var events: [RedactedDiagnosticsEvent] = []
    @Published var searchText: String = ""
    let dismissAction: () -> Void
    private var clearCutoff: Date?

    init(dismissAction: @escaping () -> Void = {}) {
        self.dismissAction = dismissAction
    }

    func update(events: [RedactedDiagnosticsEvent]) {
        if let clearCutoff {
            self.events = events.filter { $0.timestamp > clearCutoff }
        } else {
            self.events = events
        }
    }

    func clear() {
        // The store delivers events newest-first, so `events.first` is the
        // most-recent event seen. Anchoring the cutoff there ensures the
        // store's next snapshot push (same ring buffer) doesn't repopulate
        // the view; only events emitted after this clear become visible.
        clearCutoff = events.first?.timestamp ?? Date()
        events = []
    }

    /// View-side filter: case-insensitive substring across the visible
    /// row content (timestamp text + level label + category + message +
    /// metadata `key=value` pairs). Compose order is `events` (already
    /// past the clear cutoff) → search filter, so cleared events stay
    /// hidden regardless of the search term.
    var filteredEvents: [RedactedDiagnosticsEvent] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return events }
        return events.filter { event in
            event.searchableText.localizedCaseInsensitiveContains(query)
        }
    }
}

extension RedactedDiagnosticsEvent {
    /// Concatenated row text used by the overlay's search box. Mirrors
    /// what the user sees on screen so "what you see is what you can
    /// search."
    var searchableText: String {
        var parts: [String] = [
            timestamp.formatted(date: .omitted, time: .standard),
            level.rawValue,
            category,
            message,
        ]
        parts += metadata.map { "\($0.key)=\($0.value)" }
        return parts.joined(separator: " ")
    }
}

struct LiveDiagnosticsOverlayView: View {
    @ObservedObject var viewModel: LiveDiagnosticsOverlayViewModel
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = PersonalScribeTheme.Palette.for(scheme: colorScheme)

        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Live Diagnostics")
                        .font(PersonalScribeTheme.Typography.body.font.weight(.semibold))
                    Text("Verbose diagnostics stream here while the app is running.")
                        .font(PersonalScribeTheme.Typography.caption.font)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Button {
                    viewModel.clear()
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .disabled(viewModel.events.isEmpty)
                .help("Clear")
                Button(action: viewModel.dismissAction) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Close (Esc)")
            }

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                TextField("Filter…", text: $viewModel.searchText)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
            }

            if viewModel.events.isEmpty {
                Text("No diagnostics yet.")
                    .font(PersonalScribeTheme.Typography.caption.font)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else if viewModel.filteredEvents.isEmpty {
                Text("No events match \"\(viewModel.searchText)\".")
                    .font(PersonalScribeTheme.Typography.caption.font)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(viewModel.filteredEvents.enumerated()), id: \.offset) { _, event in
                            LiveDiagnosticsEventRow(event: event)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(14)
        .frame(width: 480, height: 320, alignment: .topLeading)
        .background(palette.surface)
    }
}

private struct LiveDiagnosticsEventRow: View {
    let event: RedactedDiagnosticsEvent

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(event.timestamp.formatted(date: .omitted, time: .standard))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)

                Text(event.level.rawValue.uppercased())
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(levelColor)

                Text(event.category)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            Text(event.message)
                .font(PersonalScribeTheme.Typography.caption.font.weight(.semibold))

            if event.metadata.isEmpty == false {
                Text(event.metadataSummary)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(
                cornerRadius: PersonalScribeTheme.Radius.row,
                style: .continuous
            )
            .fill(Color.primary.opacity(0.05))
        )
    }

    private var levelColor: Color {
        switch event.level {
        case .debug:
            .secondary
        case .info:
            .blue
        case .notice:
            .orange
        case .error:
            .red
        }
    }
}

private extension RedactedDiagnosticsEvent {
    var metadataSummary: String {
        metadata
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: " ")
    }
}
