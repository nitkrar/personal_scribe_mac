import Foundation

enum DiagnosticsLineRenderer {
    /// Local time with its UTC offset, e.g. `2026-10-06T00:09:45.961+01:00`.
    private static func makeTimestampFormatter(timeZone: TimeZone) -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = timeZone
        return formatter
    }

    static func render(_ event: RedactedDiagnosticsEvent, timeZone: TimeZone = .current) -> String {
        let timestampFormatter = makeTimestampFormatter(timeZone: timeZone)
        var fields: [String] = [
            timestampFormatter.string(from: event.timestamp),
            "level=\(event.level.rawValue)",
            "category=\(quoted(event.category))",
            "message=\(quoted(event.message))",
            "file=\(quoted(event.sourceLocation.file))",
            "function=\(quoted(event.sourceLocation.function))",
            "line=\(event.sourceLocation.line)",
        ]

        if let underlyingError = event.underlyingError {
            fields.append("errorType=\(quoted(underlyingError))")
        }

        for key in event.metadata.keys.sorted() {
            guard let value = event.metadata[key] else { continue }
            fields.append("\(key)=\(quoted(value))")
        }

        return fields.joined(separator: " ")
    }

    private static func quoted(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}
