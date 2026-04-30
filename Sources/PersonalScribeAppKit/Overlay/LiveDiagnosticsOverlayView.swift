import SwiftUI
import PersonalScribeCore

@MainActor
final class LiveDiagnosticsOverlayViewModel: ObservableObject {
    @Published fileprivate(set) var events: [RedactedDiagnosticsEvent] = []

    func update(events: [RedactedDiagnosticsEvent]) {
        self.events = events
    }
}

struct LiveDiagnosticsOverlayView: View {
    @ObservedObject var viewModel: LiveDiagnosticsOverlayViewModel
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = PersonalScribeTheme.Palette.for(scheme: colorScheme)

        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Live Diagnostics")
                    .font(PersonalScribeTheme.Typography.body.font.weight(.semibold))
                Text("Verbose diagnostics stream here while the app is running.")
                    .font(PersonalScribeTheme.Typography.caption.font)
                    .foregroundStyle(.secondary)
            }

            if viewModel.events.isEmpty {
                Text("No diagnostics yet.")
                    .font(PersonalScribeTheme.Typography.caption.font)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(viewModel.events.enumerated()), id: \.offset) { _, event in
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
