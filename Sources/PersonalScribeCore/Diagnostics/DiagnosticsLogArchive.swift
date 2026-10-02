import Foundation

/// Settings shared by the file sinks: the per-file size cap, the clock that
/// dates archives, and a hook fired after each size rollover.
public struct DiagnosticsLogFileOptions: Sendable {
    public var maxLogSizeBytes: Int
    public var now: @Sendable () -> Date
    public var calendar: Calendar
    public var onRollover: @Sendable () -> Void

    public init(
        maxLogSizeBytes: Int = 1_000_000,
        now: @escaping @Sendable () -> Date = Date.init,
        calendar: Calendar = .autoupdatingCurrent,
        onRollover: @escaping @Sendable () -> Void = {}
    ) {
        self.maxLogSizeBytes = maxLogSizeBytes
        self.now = now
        self.calendar = calendar
        self.onRollover = onRollover
    }
}

/// Archive file names: `<base>.<yyyy-MM-dd>.log` for a day's first archive,
/// `<base>.<yyyy-MM-dd>.<n>.log` for later ones (size rollovers, or the
/// midnight rotation after a rollover). Higher `n` is newer.
struct DiagnosticsLogArchiveName: Equatable {
    /// Active log the archive came from, e.g. `diagnostics.log`.
    let baseLogName: String
    let date: Date
    let index: Int

    static func parse(_ fileName: String, calendar: Calendar) -> DiagnosticsLogArchiveName? {
        guard fileName.hasSuffix(".log") else {
            return nil
        }
        var parts = fileName.dropLast(4).split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        var index = 0
        if parts.count >= 3, let number = Int(parts[parts.count - 1]), number > 0,
           parts[parts.count - 1].allSatisfy(\.isASCIIDigit) {
            index = number
            parts.removeLast()
        }
        guard parts.count >= 2, let date = date(from: parts.removeLast(), calendar: calendar) else {
            return nil
        }
        let stem = parts.joined(separator: ".")
        guard !stem.isEmpty else {
            return nil
        }
        return DiagnosticsLogArchiveName(baseLogName: "\(stem).log", date: date, index: index)
    }

    /// First archive URL for `activeLogURL` on `day` that doesn't exist yet.
    static func nextURL(
        forActiveLog activeLogURL: URL,
        day: Date,
        calendar: Calendar,
        fileManager: FileManager
    ) -> URL {
        let directory = activeLogURL.deletingLastPathComponent()
        let stem = activeLogURL.deletingPathExtension().lastPathComponent
        let dateString = dateFormatter(calendar: calendar).string(from: day)
        var index = 0
        while true {
            let name = index == 0 ? "\(stem).\(dateString).log" : "\(stem).\(dateString).\(index).log"
            let url = directory.appendingPathComponent(name, isDirectory: false)
            if !fileManager.fileExists(atPath: url.path) {
                return url
            }
            index += 1
        }
    }

    static func date(from string: String, calendar: Calendar) -> Date? {
        guard string.count == 10, let date = dateFormatter(calendar: calendar).date(from: string) else {
            return nil
        }
        return calendar.startOfDay(for: date)
    }

    private static func dateFormatter(calendar: Calendar) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }
}

private extension Character {
    var isASCIIDigit: Bool {
        isASCII && isNumber
    }
}
