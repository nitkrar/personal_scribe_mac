import Foundation

public struct DiagnosticsSourceLocation: Sendable, Equatable {
    public let file: String
    public let function: String
    public let line: UInt

    public init(file: String, function: String, line: UInt) {
        self.file = file
        self.function = function
        self.line = line
    }
}

public struct DiagnosticsUnderlyingError: Sendable, Equatable {
    public let typeName: String
    public let caseName: String?

    public init(typeName: String, caseName: String?) {
        self.typeName = typeName
        self.caseName = caseName
    }

    public init(_ error: any Error) {
        let description = String(describing: error)
        let candidate = description
            .split(separator: "(", maxSplits: 1)
            .first
            .map(String.init)

        self.init(
            typeName: String(reflecting: type(of: error)),
            caseName: Self.isSafeCaseName(candidate) ? candidate : nil
        )
    }

    public var rendered: String {
        guard let caseName else {
            return typeName
        }
        return "\(typeName).\(caseName)"
    }

    private static func isSafeCaseName(_ candidate: String?) -> Bool {
        guard let candidate, candidate.isEmpty == false else {
            return false
        }

        return candidate.range(
            of: "^[A-Za-z_][A-Za-z0-9_]*$",
            options: .regularExpression
        ) != nil
    }
}

public struct DiagnosticsEvent: Sendable {
    public let level: DiagnosticsLevel
    public let category: String
    public let message: String
    public let timestamp: Date
    public let underlyingError: DiagnosticsUnderlyingError?
    public let metadata: [String: String]
    public let userFacing: UserFacingDiagnostic?
    public let sourceLocation: DiagnosticsSourceLocation

    public init(
        level: DiagnosticsLevel,
        category: String,
        message: String,
        timestamp: Date,
        underlyingError: DiagnosticsUnderlyingError?,
        metadata: [String: String],
        userFacing: UserFacingDiagnostic?,
        sourceLocation: DiagnosticsSourceLocation
    ) {
        self.level = level
        self.category = category
        self.message = message
        self.timestamp = timestamp
        self.underlyingError = underlyingError
        self.metadata = metadata
        self.userFacing = userFacing
        self.sourceLocation = sourceLocation
    }
}

public struct RedactedDiagnosticsEvent: Sendable, Equatable {
    public let level: DiagnosticsLevel
    public let category: String
    public let message: String
    public let timestamp: Date
    public let underlyingError: String?
    public let metadata: [String: String]
    public let userFacing: UserFacingDiagnostic?
    public let sourceLocation: DiagnosticsSourceLocation

    public init(
        level: DiagnosticsLevel,
        category: String,
        message: String,
        timestamp: Date,
        underlyingError: String?,
        metadata: [String: String],
        userFacing: UserFacingDiagnostic?,
        sourceLocation: DiagnosticsSourceLocation
    ) {
        self.level = level
        self.category = category
        self.message = message
        self.timestamp = timestamp
        self.underlyingError = underlyingError
        self.metadata = metadata
        self.userFacing = userFacing
        self.sourceLocation = sourceLocation
    }
}
