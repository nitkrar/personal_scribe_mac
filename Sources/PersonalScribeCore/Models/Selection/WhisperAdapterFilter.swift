import Foundation

public enum WhisperAdapterFilter: String, Codable, CaseIterable, Sendable, Equatable, Hashable {
    case native
    case bridge
    case both

    public static let userDefaultsKey = "WhisperAdapterFilter"
    public static let `default`: WhisperAdapterFilter = .both

    public static func preference(defaults: UserDefaults = .standard) -> Preference<Self> {
        Preference(key: userDefaultsKey, default: .default, defaults: defaults)
    }

    public static func resolve(from defaults: UserDefaults = .standard) -> Self {
        preference(defaults: defaults).resolve()
    }

    public func persist(to defaults: UserDefaults = .standard) {
        Self.preference(defaults: defaults).persist(self)
    }

    public func filter(_ descriptors: [ModelDescriptor]) -> [ModelDescriptor] {
        descriptors.filter(includes)
    }

    public func includes(_ descriptor: ModelDescriptor) -> Bool {
        includes(descriptor.engine)
    }

    public func includes(_ engine: TranscriptionEngine) -> Bool {
        switch (self, engine) {
        case (.native, .whisperCpp), (.native, .whisperCppStreaming):
            return false
        case (.bridge, .whisperKit):
            return false
        default:
            return true
        }
    }
}

public extension TranscriptionEngine {
    var isWhisperFamily: Bool {
        switch self {
        case .whisperKit, .whisperCpp, .whisperCppStreaming:
            return true
        case .parakeetTDT, .parakeetEOU, .qwen3ASR, .diarization:
            return false
        }
    }
}
