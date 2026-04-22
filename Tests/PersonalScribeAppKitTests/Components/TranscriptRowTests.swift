import SwiftUI
import XCTest
@testable import PersonalScribeAppKit

/// Tests for `TranscriptRow` — a list-row surface showing title,
/// timestamp, and truncated body preview. Consumed by History Panel
/// and Notes Sidebar (Phase 3).
@MainActor
final class TranscriptRowTests: XCTestCase {
    // MARK: - Initializer / stored state

    func testInitializerAcceptsTitleTimestampAndPreview() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let row = TranscriptRow(
            title: "Sync notes",
            timestamp: date,
            preview: "We discussed the roadmap."
        )
        XCTAssertEqual(row.title, "Sync notes")
        XCTAssertEqual(row.timestamp, date)
        XCTAssertEqual(row.preview, "We discussed the roadmap.")
    }

    func testDefaultSelectionIsFalse() {
        let row = TranscriptRow(
            title: "T",
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            preview: "B"
        )
        XCTAssertFalse(row.isSelected)
    }

    func testSelectedStateIsStored() {
        let row = TranscriptRow(
            title: "T",
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            preview: "B",
            isSelected: true
        )
        XCTAssertTrue(row.isSelected)
    }

    // MARK: - Title truncation

    func testTitleShorterThanMaxLengthIsPreservedVerbatim() {
        let input = "Short title"
        let output = TranscriptRow.Formatters.truncate(input, maxLength: 60)
        XCTAssertEqual(output, input)
    }

    func testTitleAtExactlyMaxLengthIsPreservedVerbatim() {
        let input = String(repeating: "x", count: 60)
        let output = TranscriptRow.Formatters.truncate(input, maxLength: 60)
        XCTAssertEqual(output, input)
        XCTAssertEqual(output.count, 60)
    }

    func testTitleLongerThanMaxLengthIsTruncatedWithSingleCharEllipsis() {
        let input = String(repeating: "x", count: 100)
        let output = TranscriptRow.Formatters.truncate(input, maxLength: 60)
        XCTAssertEqual(output.count, 60)
        XCTAssertTrue(output.hasSuffix("\u{2026}"))
        XCTAssertEqual(String(output.dropLast()), String(repeating: "x", count: 59))
    }

    func testDisplayTitleAppliesTruncation() {
        let long = String(repeating: "a", count: 120)
        let row = TranscriptRow(
            title: long,
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            preview: ""
        )
        XCTAssertEqual(row.displayTitle.count, TranscriptRow.Layout.titleMaxLength)
        XCTAssertTrue(row.displayTitle.hasSuffix("\u{2026}"))
    }

    // MARK: - Body whitespace collapsing

    func testBodyCollapsesMultipleSpaces() {
        let input = "one    two"
        let output = TranscriptRow.Formatters.collapseWhitespace(input)
        XCTAssertEqual(output, "one two")
    }

    func testBodyCollapsesNewlinesAndTabs() {
        let input = "line one\nline two\tsome"
        let output = TranscriptRow.Formatters.collapseWhitespace(input)
        XCTAssertEqual(output, "line one line two some")
    }

    func testBodyEmptyStringCollapsesToEmpty() {
        XCTAssertEqual(TranscriptRow.Formatters.collapseWhitespace(""), "")
    }

    func testBodyOnlyWhitespaceCollapsesToEmpty() {
        XCTAssertEqual(TranscriptRow.Formatters.collapseWhitespace("   \n  \t"), "")
    }

    // MARK: - Relative timestamp formatting

    func testTimestampJustNowWhenLessThanOneMinuteAgo() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let ts = now.addingTimeInterval(-30)
        let out = TranscriptRow.Formatters.relativeTimestamp(from: ts, to: now)
        XCTAssertEqual(out, "Just now")
    }

    func testTimestampInFutureFallsBackToJustNow() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let ts = now.addingTimeInterval(+120) // future
        let out = TranscriptRow.Formatters.relativeTimestamp(from: ts, to: now)
        XCTAssertEqual(out, "Just now")
    }

    func testTimestampMinutesAgo() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let ts = now.addingTimeInterval(-60 * 5)
        let out = TranscriptRow.Formatters.relativeTimestamp(from: ts, to: now)
        XCTAssertEqual(out, "5m ago")
    }

    func testTimestampHoursAgo() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let ts = now.addingTimeInterval(-60 * 60 * 3)
        let out = TranscriptRow.Formatters.relativeTimestamp(from: ts, to: now)
        XCTAssertEqual(out, "3h ago")
    }

    func testTimestampDaysAgo() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let ts = now.addingTimeInterval(-60 * 60 * 24 * 3)
        let out = TranscriptRow.Formatters.relativeTimestamp(from: ts, to: now)
        XCTAssertEqual(out, "3d ago")
    }

    func testTimestampSevenDaysOrMoreSwitchesToCalendarDate() {
        // Build deterministic calendar + dates (Gregorian, UTC) so the
        // bucket boundary is free of DST effects.
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let locale = Locale(identifier: "en_US_POSIX")

        let now = cal.date(from: DateComponents(year: 2024, month: 3, day: 20))!
        let ts = cal.date(from: DateComponents(year: 2024, month: 3, day: 12))!

        let out = TranscriptRow.Formatters.relativeTimestamp(
            from: ts,
            to: now,
            calendar: cal,
            locale: locale
        )
        // We don't pin the exact glyph (locale-dependent) — assert it is
        // not one of the relative buckets and contains a month hint.
        XCTAssertFalse(out.contains("ago"))
        XCTAssertFalse(out == "Just now")
        XCTAssertTrue(out.contains("Mar") || out.contains("3"))
    }

    func testTimestampDifferentYearIncludesYear() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let locale = Locale(identifier: "en_US_POSIX")

        let now = cal.date(from: DateComponents(year: 2024, month: 3, day: 20))!
        let ts = cal.date(from: DateComponents(year: 2022, month: 5, day: 10))!

        let out = TranscriptRow.Formatters.relativeTimestamp(
            from: ts,
            to: now,
            calendar: cal,
            locale: locale
        )
        XCTAssertTrue(out.contains("2022"), "Expected year in output, got: \(out)")
    }

    func testDisplayTimestampUsesReferenceDateForStableFormatting() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let ts = now.addingTimeInterval(-60 * 10)
        let row = TranscriptRow(
            title: "T",
            timestamp: ts,
            preview: "B",
            referenceDate: now
        )
        XCTAssertEqual(row.displayTimestamp, "10m ago")
    }

    // MARK: - Layout constants locked in

    func testPreviewLineLimitIsTwo() {
        XCTAssertEqual(TranscriptRow.Layout.previewLineLimit, 2)
    }

    func testTitleMaxLengthIsSixty() {
        XCTAssertEqual(TranscriptRow.Layout.titleMaxLength, 60)
    }

    // MARK: - DisplayStyle (mockup-gap A.1)

    func testDefaultDisplayStyleIsSummary() {
        let row = TranscriptRow(
            title: "Sync",
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            preview: "Body"
        )
        XCTAssertEqual(row.displayStyle, .summary)
    }

    func testDetailInitializerUsesDetailDisplayStyle() {
        let row = TranscriptRow(
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            preview: "Body"
        )
        XCTAssertEqual(row.displayStyle, .detail)
    }

    func testDetailStyleHasEmptyDisplayTitle() {
        // The Transcriptions tab row drops the separate title surface —
        // the preview is the content. displayTitle must be empty so the
        // body does not render a duplicated title slot.
        let row = TranscriptRow(
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            preview: "Once upon a time"
        )
        XCTAssertEqual(row.displayTitle, "")
    }

    func testSummaryStyleKeepsTitleForHomeTabCallers() {
        let row = TranscriptRow(
            title: "Sync notes",
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            preview: "Body"
        )
        XCTAssertEqual(row.displayStyle, .summary)
        XCTAssertEqual(row.displayTitle, "Sync notes")
    }

    func testDeleteControlAppearsForHoveredDetailRowsWhenDeleteActionAvailable() {
        XCTAssertTrue(
            TranscriptRow.showsDeleteControl(
                displayStyle: .detail,
                isHovered: true,
                hasDeleteAction: true
            )
        )
    }

    func testDeleteControlStaysHiddenWithoutHoverOrDeleteAction() {
        XCTAssertFalse(
            TranscriptRow.showsDeleteControl(
                displayStyle: .detail,
                isHovered: false,
                hasDeleteAction: true
            )
        )
        XCTAssertFalse(
            TranscriptRow.showsDeleteControl(
                displayStyle: .detail,
                isHovered: true,
                hasDeleteAction: false
            )
        )
    }

    func testDeleteControlNeverAppearsForSummaryRows() {
        XCTAssertFalse(
            TranscriptRow.showsDeleteControl(
                displayStyle: .summary,
                isHovered: true,
                hasDeleteAction: true
            )
        )
    }

    // MARK: - Row height (mockup-gap A.3)

    func testDetailMinHeightEqualsRowHeightTall() {
        // Detail-style rows are pinned to RowHeight.tall (56pt) so the
        // Transcriptions list matches the mockup's two-line body + time
        // cadence.
        XCTAssertEqual(
            TranscriptRow.Layout.detailMinHeight,
            PersonalScribeTheme.RowHeight.tall
        )
    }

    func testDetailMinHeightIs56() {
        // Direct-value lock-in — guards against a future
        // `RowHeight.tall` tweak silently shrinking the Transcriptions
        // row cadence. Source of truth confirmed in
        // PersonalScribeThemeTests.testRowHeightTallIs56.
        XCTAssertEqual(TranscriptRow.Layout.detailMinHeight, 56)
    }

    // MARK: - Wall-clock timestamp (mockup-gap A.4)

    func testWallClockFormatterReturnsShortTimeString() {
        // 2026-04-20 14:34:00 UTC — formatted with en_US_POSIX gives a
        // stable "2:34 PM" glyph independent of host locale.
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let locale = Locale(identifier: "en_US_POSIX")
        let ts = cal.date(
            from: DateComponents(
                year: 2026, month: 4, day: 20,
                hour: 14, minute: 34, second: 0
            )
        )!

        let out = TranscriptRow.Formatters.wallClockTimestamp(
            from: ts,
            calendar: cal,
            locale: locale,
            timeZone: TimeZone(identifier: "UTC")!
        )

        // Foundation emits U+202F (narrow no-break space) between time and
        // AM/PM on macOS 13+. Normalize to regular space before comparing.
        let normalized = out
            .replacingOccurrences(of: "\u{202F}", with: " ")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
        XCTAssertEqual(normalized, "2:34 PM")
    }

    func testDetailStyleUsesWallClockTimestamp() {
        // Detail-style rows show wall-clock times ("2:34 PM"), not the
        // relative-bucket string used by Home ("5m ago"). The underlying
        // formatter is locale-dependent on the device default, so assert
        // shape rather than exact glyph: must NOT contain "ago" or
        // "Just now".
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let ts = now.addingTimeInterval(-60 * 10)
        let row = TranscriptRow(
            timestamp: ts,
            preview: "Body",
            referenceDate: now
        )

        let out = row.displayTimestamp
        XCTAssertFalse(out.contains("ago"), "Detail timestamp leaked relative glyph: \(out)")
        XCTAssertNotEqual(out, "Just now")
    }

    func testSummaryStyleStillUsesRelativeTimestamp() {
        // Home-tab callers (summary init) keep the relative-bucket
        // behaviour — "10m ago" for a 10-minute-old entry.
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let ts = now.addingTimeInterval(-60 * 10)
        let row = TranscriptRow(
            title: "T",
            timestamp: ts,
            preview: "Body",
            referenceDate: now
        )
        XCTAssertEqual(row.displayTimestamp, "10m ago")
    }
}
