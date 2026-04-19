import FluidAudio
import Foundation
import SeshatCore

public enum FluidAudioRuntimeVariant: Sendable, Equatable {
    case parakeetTDT06Bv2
    case parakeetTDT06Bv3
    case parakeetTDTCTC110M

    public init(descriptor: ModelDescriptor) throws {
        switch descriptor.id {
        case BuiltInModelCatalog.parakeetTDT06Bv2.id:
            self = .parakeetTDT06Bv2
        case BuiltInModelCatalog.parakeetTDT06Bv3.id:
            self = .parakeetTDT06Bv3
        case BuiltInModelCatalog.parakeetTDTCTC110M.id:
            self = .parakeetTDTCTC110M
        default:
            throw ModelSelectionError.unknownVoiceModelID(descriptor.id)
        }
    }

    var asrModelVersion: AsrModelVersion {
        switch self {
        case .parakeetTDT06Bv2:
            .v2
        case .parakeetTDT06Bv3:
            .v3
        case .parakeetTDTCTC110M:
            .tdtCtc110m
        }
    }
}
