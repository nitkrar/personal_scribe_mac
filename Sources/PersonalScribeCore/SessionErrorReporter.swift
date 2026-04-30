import Foundation

public struct ReportedError: Sendable, Equatable {
    public let mappedError: PersonalScribeError
    public let userMessage: String
    public let detail: String
    public let timestamp: Date
    public let category: String
    public let context: [String: String]

    public init(
        mappedError: PersonalScribeError,
        userMessage: String,
        detail: String,
        timestamp: Date,
        category: String,
        context: [String: String] = [:]
    ) {
        self.mappedError = mappedError
        self.userMessage = userMessage
        self.detail = detail
        self.timestamp = timestamp
        self.category = category
        self.context = context
    }
}

public struct SessionErrorReporter: Sendable {
    private let logger: PersonalScribeLogger
    private let now: @Sendable () -> Date
    private let writer: SessionErrorLogWriter

    public init(
        logger: PersonalScribeLogger = PersonalScribeLogger(category: PersonalScribeLogCategory.session)
    ) {
        self.init(
            logger: logger,
            now: Date.init,
            storageLocatorProvider: { AppConfig.liveStorageLocator() },
            atomicFileWriter: FileManagerAtomicFileWriter()
        )
    }

    init(
        logger: PersonalScribeLogger,
        now: @escaping @Sendable () -> Date,
        storageLocatorProvider: @escaping @Sendable () -> any StorageLocator,
        atomicFileWriter: any AtomicFileWriter,
        maxLogSizeBytes: Int = 1_000_000
    ) {
        self.logger = logger
        self.now = now
        writer = SessionErrorLogWriter(
            logger: logger,
            storageLocatorProvider: storageLocatorProvider,
            atomicFileWriter: atomicFileWriter,
            maxLogSizeBytes: maxLogSizeBytes
        )
    }

    @discardableResult
    public func report(
        _ error: any Error,
        mappedError: PersonalScribeError,
        category: String,
        detail: String,
        context: [String: String] = [:],
        file: StaticString = #fileID,
        function: StaticString = #function,
        line: UInt = #line
    ) -> ReportedError {
        let reported = ReportedError(
            mappedError: mappedError,
            userMessage: Self.userMessage(for: mappedError),
            detail: detail,
            timestamp: now(),
            category: category,
            context: context
        )
        let fileString = String(describing: file)
        let functionString = String(describing: function)
        logger.error(
            "Reported session error [\(category)] mappedError=\(mappedError) detail=\(detail)",
            error: error,
            file: file,
            line: line
        )
        Task {
            await writer.append(
                SessionErrorLogEntry(
                    reported: reported,
                    file: fileString,
                    function: functionString,
                    line: line
                )
            )
        }
        return reported
    }

    /// Cap on the user-facing message rendered in the response card.
    /// Per the #092 follow-up scope: fit on a single response-card row
    /// without wrapping. The combined `errorDescription + recoverySuggestion`
    /// for a few `PersonalScribeError` cases (notably `.invalidActiveMode`
    /// at ~149 chars) overruns this; the helper degrades gracefully by
    /// dropping the suggestion first, then truncating the description
    /// only as a last resort.
    static let userMessageMaxLength = 80

    private static func userMessage(for error: PersonalScribeError) -> String {
        let description = error.errorDescription ?? "Something went wrong."
        guard let suggestion = error.recoverySuggestion else {
            return cap(description)
        }
        let combined = "\(description) \(suggestion)"
        if combined.count <= userMessageMaxLength {
            return combined
        }
        return cap(description)
    }

    private static func cap(_ message: String) -> String {
        guard message.count > userMessageMaxLength else {
            return message
        }
        let endIndex = message.index(message.startIndex, offsetBy: userMessageMaxLength - 1)
        return String(message[..<endIndex]) + "…"
    }
}

private struct SessionErrorLogEntry: Sendable {
    let reported: ReportedError
    let file: String
    let function: String
    let line: UInt
}

private actor SessionErrorLogWriter {
    private static let logFileName = "errors.log"
    private static let rotatedLogFileName = "errors.log.1"

    private let logger: PersonalScribeLogger
    private let storageLocatorProvider: @Sendable () -> any StorageLocator
    private let atomicFileWriter: any AtomicFileWriter
    private let fileManager = FileManager.default
    private let maxLogSizeBytes: Int

    init(
        logger: PersonalScribeLogger,
        storageLocatorProvider: @escaping @Sendable () -> any StorageLocator,
        atomicFileWriter: any AtomicFileWriter,
        maxLogSizeBytes: Int
    ) {
        self.logger = logger
        self.storageLocatorProvider = storageLocatorProvider
        self.atomicFileWriter = atomicFileWriter
        self.maxLogSizeBytes = maxLogSizeBytes
    }

    func append(_ entry: SessionErrorLogEntry) async {
        let locator = storageLocatorProvider()
        let logDirectoryURL = locator.url(for: .logs)
        let logURL = logDirectoryURL.appendingPathComponent(Self.logFileName)
        let rotatedLogURL = logDirectoryURL.appendingPathComponent(Self.rotatedLogFileName)
        let renderedEntry = render(entry)

        do {
            try locator.ensureDirectoriesExist()
            try rotateIfNeeded(
                logURL: logURL,
                rotatedLogURL: rotatedLogURL,
                incomingBytes: renderedEntry.lengthOfBytes(using: .utf8)
            )

            let existingContents = (try? String(contentsOf: logURL, encoding: .utf8)) ?? ""
            let updatedContents = existingContents + renderedEntry
            try atomicFileWriter.replaceItem(at: logURL, permissions: 0o600) { temporaryURL in
                try updatedContents.write(to: temporaryURL, atomically: false, encoding: .utf8)
            }
        } catch {
            logger.error("Failed to append session error log entry", error: error)
        }
    }

    private func rotateIfNeeded(
        logURL: URL,
        rotatedLogURL: URL,
        incomingBytes: Int
    ) throws {
        guard fileManager.fileExists(atPath: logURL.path) else {
            return
        }

        let attributes = try fileManager.attributesOfItem(atPath: logURL.path)
        let existingBytes = (attributes[.size] as? NSNumber)?.intValue ?? 0
        guard existingBytes + incomingBytes > maxLogSizeBytes else {
            return
        }

        if fileManager.fileExists(atPath: rotatedLogURL.path) {
            try fileManager.removeItem(at: rotatedLogURL)
        }
        try fileManager.moveItem(at: logURL, to: rotatedLogURL)
    }

    private func render(_ entry: SessionErrorLogEntry) -> String {
        let reported = entry.reported
        let timestamp = Self.makeTimestampFormatter().string(from: reported.timestamp)
        let sanitizedUserMessage = sanitize(reported.userMessage)
        let sanitizedDetail = sanitize(reported.detail)
        let renderedContext = reported.context
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\(sanitize($0.value))" }
            .joined(separator: " ")
        let contextSuffix = renderedContext.isEmpty ? "" : " \(renderedContext)"

        return """
        \(timestamp) [\(reported.category)] userMessage=\(sanitizedUserMessage) mappedError=\(reported.mappedError) detail=\(sanitizedDetail) file=\(sanitize(entry.file)) function=\(sanitize(entry.function)) line=\(entry.line)\(contextSuffix)

        """
    }

    private func sanitize(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
    }

    private static func makeTimestampFormatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }
}
