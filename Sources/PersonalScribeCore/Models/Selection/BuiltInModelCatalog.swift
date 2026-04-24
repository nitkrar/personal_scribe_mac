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
        // FluidAudio's `Repo.parakeetV2.folderName` (default rule strips
        // the `-coreml` suffix from `name`). Verified against
        // `FluidAudio/Sources/FluidAudio/ModelNames.swift` switch.
        repoFolderName: "parakeet-tdt-0.6b-v2",
        kind: .asr,
        shortDescription: "High-accuracy default — balanced RAM and speed.",
        architecture: "FastConformer-TDT",
        repository: "FluidInference/parakeet-tdt-0.6b-v2-coreml",
        revision: "ee09c569f73759e6d44c9bd16766f477b2b36d39",
        requiredRelativePaths: splitFrontendRequiredPaths,
        // Sum of required `.mlmodelc` + `parakeet_vocab.json` per HF
        // tree API at the pinned revision (2026-04-25). Refreshed from
        // the prior 450M estimate.
        approximateSizeBytes: 464_413_247,
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
        // FluidAudio's `Repo.parakeetTdtCtc110m.folderName` (explicit
        // case at `ModelNames.swift:151-152` returns
        // `"parakeet-tdt-ctc-110m"` — drops the `-coreml` suffix the
        // repo name carries on HF).
        repoFolderName: "parakeet-tdt-ctc-110m",
        kind: .asr,
        shortDescription: "Lightweight — faster, lower accuracy, minimal RAM.",
        architecture: "Hybrid FastConformer-TDT-CTC",
        repository: "FluidInference/parakeet-tdt-ctc-110m-coreml",
        revision: "9bc92ead6e8f17eca92a869fd578ae76842b82ba",
        requiredRelativePaths: fusedFrontendRequiredPaths,
        // Sum of required `.mlmodelc` (Preprocessor + Decoder +
        // JointDecision, fused frontend skips Encoder) + vocab per HF
        // tree API at the pinned revision (2026-04-25). Prior estimate
        // (407M) was nearly 2× the actual download.
        approximateSizeBytes: 227_466_209,
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

    public static let parakeetTDT06Bv3 = ModelDescriptor(
        id: "parakeet-tdt-0.6b-v3",
        displayName: "Parakeet TDT 0.6B v3",
        // `Repo.parakeet.folderName` — default rule strips `-coreml`
        // from `parakeet-tdt-0.6b-v3-coreml`.
        repoFolderName: "parakeet-tdt-0.6b-v3",
        kind: .asr,
        shortDescription: "Multilingual (25 European languages) — same compute as v2.",
        architecture: "FastConformer-TDT",
        repository: "FluidInference/parakeet-tdt-0.6b-v3-coreml",
        // Pinned to the current HuggingFace `main` HEAD (2026-04-25).
        // Was previously `"main"` (drift risk).
        revision: "775be920d492d20e9e522ee0a969414fd6e6e0f7",
        requiredRelativePaths: splitFrontendRequiredPaths,
        // Sum of required `.mlmodelc` + vocab per HF tree API at the
        // pinned revision (2026-04-25). Prior 700M estimate was high.
        approximateSizeBytes: 483_103_089,
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
