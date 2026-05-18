import Foundation

extension TranscriptionEngine: Codable {
    private enum CodableValue: String, Codable {
        case parakeetTDT
        case parakeetEOU
        case qwen3ASR
        case whisperKit
        case whisperCpp
        case diarization
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(CodableValue.self)

        switch rawValue {
        case .parakeetTDT:
            self = .parakeetTDT
        case .parakeetEOU:
            self = .parakeetEOU
        case .qwen3ASR:
            self = .qwen3ASR
        case .whisperKit:
            self = .whisperKit
        case .whisperCpp:
            self = .whisperCpp
        case .diarization:
            self = .diarization
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch self {
        case .parakeetTDT:
            try container.encode(CodableValue.parakeetTDT)
        case .parakeetEOU:
            try container.encode(CodableValue.parakeetEOU)
        case .qwen3ASR:
            try container.encode(CodableValue.qwen3ASR)
        case .whisperKit:
            try container.encode(CodableValue.whisperKit)
        case .whisperCpp:
            try container.encode(CodableValue.whisperCpp)
        case .diarization:
            try container.encode(CodableValue.diarization)
        }
    }
}
