import SwiftUI
import PersonalScribeCore

struct NotesContextPanel: View {
    struct MetadataItem: Equatable {
        let title: String
        let value: String
    }

    let selectedEntry: TranscriptEntry?
    let associatedAudioURL: URL?
    let calendar: Calendar
    let locale: Locale
    let timeZone: TimeZone

    @Environment(\.colorScheme) private var colorScheme

    init(
        selectedEntry: TranscriptEntry?,
        associatedAudioURL: URL? = nil,
        calendar: Calendar = .autoupdatingCurrent,
        locale: Locale = .autoupdatingCurrent,
        timeZone: TimeZone = .autoupdatingCurrent
    ) {
        self.selectedEntry = selectedEntry
        self.associatedAudioURL = associatedAudioURL
        self.calendar = calendar
        self.locale = locale
        self.timeZone = timeZone
    }

    var metadataItems: [MetadataItem] {
        guard let selectedEntry else {
            return []
        }

        return [
            MetadataItem(
                title: "Recorded",
                value: Formatters.timestamp(
                    selectedEntry.timestamp,
                    calendar: calendar,
                    locale: locale,
                    timeZone: timeZone
                )
            ),
            MetadataItem(
                title: "Audio Duration",
                value: AudioPlayerThumbnail.Formatters.formatDuration(selectedEntry.audioDuration)
            ),
            MetadataItem(
                title: "Processing",
                value: AudioPlayerThumbnail.Formatters.formatDuration(selectedEntry.processingDuration)
            ),
        ]
    }

    var showsAudioThumbnail: Bool {
        selectedEntry != nil && associatedAudioURL != nil
    }

    var emptyStateText: String {
        "Select a transcript to inspect its metadata."
    }

    var body: some View {
        let palette = PersonalScribeTheme.Palette.for(scheme: colorScheme)

        VStack(alignment: .leading, spacing: Layout.sectionSpacing) {
            Text("Details")
                .font(PersonalScribeTheme.Typography.body.font.weight(.semibold))
                .foregroundStyle(palette.primaryText)

            if let selectedEntry {
                if showsAudioThumbnail {
                    AudioPlayerThumbnail(durationSeconds: selectedEntry.audioDuration)
                }

                ForEach(metadataItems, id: \.title) { item in
                    MetadataRow(item: item)
                }
            } else {
                Text(emptyStateText)
                    .font(PersonalScribeTheme.Typography.body.font)
                    .foregroundStyle(palette.secondaryText)
            }

            Spacer(minLength: 0)
        }
        .padding(Layout.panelPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(palette.elevatedSurface)
    }
}

private extension NotesContextPanel {
    enum Layout {
        static let sectionSpacing: CGFloat = 16
        static let panelPadding: CGFloat = 16
    }

    struct MetadataRow: View {
        let item: MetadataItem

        @Environment(\.colorScheme) private var colorScheme

        var body: some View {
            let palette = PersonalScribeTheme.Palette.for(scheme: colorScheme)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(PersonalScribeTheme.Typography.caption.font.weight(.semibold))
                    .foregroundStyle(palette.secondaryText)

                Text(item.value)
                    .font(PersonalScribeTheme.Typography.body.font)
                    .foregroundStyle(palette.primaryText)
            }
        }
    }

    enum Formatters {
        static func timestamp(
            _ date: Date,
            calendar: Calendar,
            locale: Locale,
            timeZone: TimeZone
        ) -> String {
            let formatter = DateFormatter()
            formatter.calendar = calendar
            formatter.locale = locale
            formatter.timeZone = timeZone
            formatter.dateFormat = "MMM d, yyyy 'at' h:mm a"
            return formatter.string(from: date)
        }
    }
}
