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

    // Benchmark numbers sourced from each model's HuggingFace card
    // (NVIDIA Open ASR leaderboard, A100, batch 128). See the
    // individual descriptors below for the per-model citation. The
    // Settings info popover consumes these directly; the
    // computed-relative presenter ranks models against each other to
    // derive the "Fastest / Fast / Slow" and "High / Medium / Low"
    // labels at render time.

    public static let parakeetTDT06Bv2 = ModelDescriptor(
        id: "parakeet-tdt-0.6b-v2",
        displayName: "Parakeet TDT 0.6B",
        shortDescription: "High-accuracy default — balanced RAM and speed.",
        architecture: "FastConformer-TDT",
        repository: "FluidInference/parakeet-tdt-0.6b-v2-coreml",
        revision: "ee09c569f73759e6d44c9bd16766f477b2b36d39",
        requiredRelativePaths: splitFrontendRequiredPaths,
        approximateSizeBytes: 450_000_000,
        engine: .parakeetTDT,
        // huggingface.co/nvidia/parakeet-tdt-0.6b-v2 (2026-04-22):
        // avg WER 6.05% (test-clean 1.69%, test-other 3.19%),
        // RTFx 3386 on HF Open ASR leaderboard (batch 128).
        performance: ModelPerformance(
            averageWER: 6.05,
            rtfx: 3386,
            parameterCount: 600_000_000
        )
    )

    /// The catalog's default model id — used by legacy code paths that still read a
    /// fixed-default string rather than consulting `defaultActiveDescriptor`.
    public static let defaultModelId: String = parakeetTDT06Bv2.id

    public static let parakeetTDTCTC110M = ModelDescriptor(
        id: "parakeet-tdt-ctc-110m",
        displayName: "Parakeet TDT-CTC 110M",
        shortDescription: "Lightweight — faster, lower accuracy, minimal RAM.",
        architecture: "Hybrid FastConformer-TDT-CTC",
        repository: "FluidInference/parakeet-tdt-ctc-110m-coreml",
        revision: "9bc92ead6e8f17eca92a869fd578ae76842b82ba",
        requiredRelativePaths: fusedFrontendRequiredPaths,
        approximateSizeBytes: 407_000_000,
        engine: .parakeetTDT,
        // huggingface.co/nvidia/parakeet-tdt_ctc-110m (2026-04-22):
        // avg WER 7.49% (test-clean 2.4%, test-other 5.2%),
        // RTFx ~5345 on HF Open ASR leaderboard. 110M params.
        performance: ModelPerformance(
            averageWER: 7.49,
            rtfx: 5345,
            parameterCount: 110_000_000
        )
    )

    // The authoritative Layer 6 plan still leaves the v3 revision pin open.
    // Keep the catalog additive for Stage 1, but leave `defaultActiveDescriptor`
    // on the pinned v2 descriptor until main session supplies the exact pin.
    public static let parakeetTDT06Bv3 = ModelDescriptor(
        id: "parakeet-tdt-0.6b-v3",
        displayName: "Parakeet TDT 0.6B v3",
        shortDescription: "Newer 0.6B release — updated weights, larger disk footprint.",
        architecture: "FastConformer-TDT",
        repository: "FluidInference/parakeet-tdt-0.6b-v3-coreml",
        revision: "main",
        requiredRelativePaths: splitFrontendRequiredPaths,
        approximateSizeBytes: 700_000_000,
        engine: .parakeetTDT,
        // huggingface.co/nvidia/parakeet-tdt-0.6b-v3 (2026-04-22):
        // avg WER 6.34% (test-clean 1.93%, test-other 3.59%),
        // RTFx 3333. Released 2025-08-14; 25 European languages.
        performance: ModelPerformance(
            averageWER: 6.34,
            rtfx: 3333,
            parameterCount: 600_000_000
        )
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
