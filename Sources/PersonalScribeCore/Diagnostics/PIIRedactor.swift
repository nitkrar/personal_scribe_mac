import Foundation

public struct PIIRedactor: Sendable {
    private static let safeKeys: Set<String> = [
        "level",
        "category",
        "mappedError",
        "stage",
        "mode",
        "descriptorID",
        "pipelineShape",
        "errorType",
    ]

    public init() {}

    public func redact(_ event: DiagnosticsEvent) -> RedactedDiagnosticsEvent {
        RedactedDiagnosticsEvent(
            level: event.level,
            category: normalize(event.category),
            message: normalize(redactPaths(in: event.message)),
            timestamp: event.timestamp,
            underlyingError: event.underlyingError.map { normalize($0.rendered) },
            metadata: redactMetadata(event.metadata),
            userFacing: event.userFacing,
            sourceLocation: DiagnosticsSourceLocation(
                file: normalize(redactPaths(in: event.sourceLocation.file)),
                function: normalize(redactPaths(in: event.sourceLocation.function)),
                line: event.sourceLocation.line
            )
        )
    }

    private func redactMetadata(_ metadata: [String: String]) -> [String: String] {
        var redacted: [String: String] = [:]
        redacted.reserveCapacity(metadata.count)

        for (key, value) in metadata {
            if Self.safeKeys.contains(key) {
                redacted[key] = normalize(redactPaths(in: value))
                continue
            }

            if isAlwaysRedactedKey(key) {
                redacted[key] = "<redacted>"
                continue
            }

            redacted[key] = normalize(redactPaths(in: value))
        }

        return redacted
    }

    private func isAlwaysRedactedKey(_ key: String) -> Bool {
        key.range(
            of: "transcript|path|deviceName|windowTitle|appName|audioFile|userMessage",
            options: [.regularExpression, .caseInsensitive]
        ) != nil
    }

    private func redactPaths(in value: String) -> String {
        value.replacingOccurrences(
            of: "/Users/[^/]+",
            with: "/Users/<redacted>",
            options: .regularExpression
        )
    }

    private func normalize(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
    }
}
