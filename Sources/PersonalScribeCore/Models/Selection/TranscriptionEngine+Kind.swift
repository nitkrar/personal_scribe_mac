import Foundation

/// Computed `kind` mapping per #078 L2: engine is canonical, kind is
/// derived. This file lives in isolation so Phase H.6's delete +
/// rename pass (`ModelDescriptor.kind` field removal) is a clean
/// touchpoint.
///
/// During the parallel-build phase the stored `ModelDescriptor.kind`
/// field continues to exist alongside this accessor — catalog
/// descriptors keep passing `kind:` and `BuiltInModelCatalogTests`
/// passes unchanged. Tests in
/// `Tests/PersonalScribeCoreTests/Models/TranscriptionEngineKindTests.swift`
/// pin the four hardcoded mappings and a convention-consistency check
/// against the catalog.
extension TranscriptionEngine {
    public var kind: ModelKind {
        switch self {
        case .parakeetTDT:
            return .asr
        case .qwen3ASR:
            return .asr
        case .whisperKit:
            return .asr
        case .whisperKitStreaming:
            return .streamingASR
        case .whisperCpp:
            return .asr
        case .whisperCppStreaming:
            return .streamingASR
        case .parakeetEOU:
            return .streamingASR
        case .diarization:
            return .diarization
        }
    }
}
