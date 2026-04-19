import Foundation

public enum BuiltInModelCatalog {
    private static let splitFrontendRequiredPaths = [
        "Preprocessor.mlmodelc/coremldata.bin",
        "Encoder.mlmodelc/coremldata.bin",
        "Decoder.mlmodelc/coremldata.bin",
        "JointDecision.mlmodelc/coremldata.bin",
        "parakeet_vocab.json",
    ]

    private static let fusedFrontendRequiredPaths = [
        "Preprocessor.mlmodelc/coremldata.bin",
        "Decoder.mlmodelc/coremldata.bin",
        "JointDecision.mlmodelc/coremldata.bin",
        "parakeet_vocab.json",
    ]

    public static let parakeetTDT06Bv2 = ModelRegistry.parakeetTDT06Bv2

    public static let parakeetTDTCTC110M = ModelDescriptor(
        id: "parakeet-tdt-ctc-110m",
        displayName: "Parakeet TDT-CTC 110M",
        repository: "FluidInference/parakeet-tdt-ctc-110m-coreml",
        revision: "9bc92ead6e8f17eca92a869fd578ae76842b82ba",
        requiredRelativePaths: fusedFrontendRequiredPaths,
        approximateSizeBytes: 407_000_000,
        engine: .parakeetTDT
    )

    // The authoritative Layer 6 plan still leaves the v3 revision pin open.
    // Keep the catalog additive for Stage 1, but leave `defaultActiveDescriptor`
    // on the pinned v2 descriptor until main session supplies the exact pin.
    public static let parakeetTDT06Bv3 = ModelDescriptor(
        id: "parakeet-tdt-0.6b-v3",
        displayName: "Parakeet TDT 0.6B v3",
        repository: "FluidInference/parakeet-tdt-0.6b-v3-coreml",
        revision: "main",
        requiredRelativePaths: splitFrontendRequiredPaths,
        approximateSizeBytes: 700_000_000,
        engine: .parakeetTDT
    )

    public static let registeredModels: [ModelDescriptor] = [
        parakeetTDT06Bv2,
        parakeetTDTCTC110M,
        parakeetTDT06Bv3,
    ]

    public static let defaultActiveDescriptor = ActiveModelDescriptor(
        voiceModel: parakeetTDT06Bv2,
        aiModelID: nil
    )

    public static func descriptor(for id: String) -> ModelDescriptor? {
        registeredModels.first { $0.id == id }
    }
}
