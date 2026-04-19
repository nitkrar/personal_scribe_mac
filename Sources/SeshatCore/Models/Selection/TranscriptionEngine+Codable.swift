import Foundation

extension TranscriptionEngine: Codable {
    private enum CodableValue: String, Codable {
        case parakeetTDT
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(CodableValue.self)

        switch rawValue {
        case .parakeetTDT:
            self = .parakeetTDT
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch self {
        case .parakeetTDT:
            try container.encode(CodableValue.parakeetTDT)
        }
    }
}
