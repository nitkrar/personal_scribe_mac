import XCTest
@testable import PersonalScribeAppKit

@MainActor
final class NotesContextPanelTests: XCTestCase {
    func testShowsSelectedEntryMetadata() {
        let entry = makeNotesEntry(
            index: 1,
            text: "Quarterly review notes",
            audioDuration: 83,
            processingDuration: 9
        )
        let panel = NotesContextPanel(
            selectedEntry: entry,
            calendar: fixedCalendar(),
            locale: Locale(identifier: "en_US_POSIX"),
            timeZone: TimeZone(secondsFromGMT: 0)!
        )

        XCTAssertEqual(
            panel.metadataItems,
            [
                .init(title: "Recorded", value: "Jan 1, 1970 at 12:01 AM"),
                .init(title: "Audio Duration", value: "1:23"),
                .init(title: "Processing", value: "0:09"),
            ]
        )
    }

    func testOmitsAudioThumbnailWithoutAssociatedAudioURL() {
        let entry = makeNotesEntry(index: 1, text: "Quarterly review notes")
        let panel = NotesContextPanel(selectedEntry: entry)

        XCTAssertFalse(panel.showsAudioThumbnail)
    }

    private func fixedCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }
}
