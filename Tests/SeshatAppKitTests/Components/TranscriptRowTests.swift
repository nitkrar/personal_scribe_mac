import SwiftUI
import XCTest
@testable import SeshatAppKit

/// Tests for `TranscriptRow` — a list-row surface showing title,
/// timestamp, and truncated body preview. Consumed by History Panel
/// and Notes Sidebar (Phase 3).
final class TranscriptRowTests: XCTestCase {
    // MARK: - Initializer / stored state

    func testInitializerAcceptsTitleTimestampAndBody() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let row = TranscriptRow(
            title: "Sync notes",
            timestamp: date,
            body: "We discussed the roadmap."
        )
        XCTAssertEqual(row.title, "Sync notes")
        XCTAssertEqual(row.timestamp, date)
        XCTAssertEqual(row.body, "We discussed the roadmap.")
    }

    func testDefaultSelectionIsFalse() {
        let row = TranscriptRow(
            title: "T",
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            body: "B"
        )
        XCTAssertFalse(row.isSelected)
    }

    func testSelectedStateIsStored() {
        let row = TranscriptRow(
            title: "T",
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            body: "B",
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
        XCTAssertEqual(output.dropLast(), String(repeating: "x", count: 59))
    }

    func testDisplayTitleAppliesTruncation() {
        let long = String(repeating: "a", count: 120)
        let row = TranscriptRow(
            title: long,
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            body: ""
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
            body: "B",
            referenceDate: now
        )
        XCTAssertEqual(row.displayTimestamp, "10m ago")
    }

    // MARK: - Layout constants locked in

    func testBodyLineLimitIsTwo() {
        XCTAssertEqual(TranscriptRow.Layout.bodyLineLimit, 2)
    }

    func testTitleMaxLengthIsSixty() {
        XCTAssertEqual(TranscriptRow.Layout.titleMaxLength, 60)
    }
}
