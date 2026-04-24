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

    // MARK: - Streaming ASR (parakeet realtime EOU)
    //
    // Parakeet 120M with end-of-utterance detection. Three chunk-size
    // variants (160ms, 320ms, 1280ms) under one HuggingFace repo,
    // `parakeet-realtime-eou-120m-coreml`, with FluidAudio's `subPath`
    // selecting the variant. Drives `StreamingEouAsrManager` (separate
    // from `AsrManager`) — adapter not yet wired in
    // PersonalScribeTranscription, so downloads via this descriptor
    // currently fail with `unknownVoiceModelID` (interim).
    private static let parakeetEouRequiredPaths = [
        "streaming_encoder.mlmodelc/coremldata.bin",
        "decoder.mlmodelc/coremldata.bin",
        "joint_decision.mlmodelc/coremldata.bin",
        "vocab.json",
    ]

    public static let parakeetEou160ms = ModelDescriptor(
        id: "parakeet-realtime-eou-120m-160ms",
        displayName: "Parakeet Realtime EOU 120M (160ms)",
        repoFolderName: "parakeet-eou-streaming/160ms",
        kind: .streamingASR,
        shortDescription: "Streaming ASR with 160ms chunks — lowest latency.",
        architecture: "Streaming FastConformer-TDT + EOU head",
        repository: "FluidInference/parakeet-realtime-eou-120m-coreml",
        revision: "40a23f4c0b333aa17ad8c0f2ea47ec2347f2f355",
        requiredRelativePaths: parakeetEouRequiredPaths,
        approximateSizeBytes: 224_047_838,
        engine: .parakeetEOU
    )

    public static let parakeetEou320ms = ModelDescriptor(
        id: "parakeet-realtime-eou-120m-320ms",
        displayName: "Parakeet Realtime EOU 120M (320ms)",
        repoFolderName: "parakeet-eou-streaming/320ms",
        kind: .streamingASR,
        shortDescription: "Streaming ASR with 320ms chunks — balanced.",
        architecture: "Streaming FastConformer-TDT + EOU head",
        repository: "FluidInference/parakeet-realtime-eou-120m-coreml",
        revision: "40a23f4c0b333aa17ad8c0f2ea47ec2347f2f355",
        requiredRelativePaths: parakeetEouRequiredPaths,
        approximateSizeBytes: 224_238_270,
        engine: .parakeetEOU
    )

    public static let parakeetEou1280ms = ModelDescriptor(
        id: "parakeet-realtime-eou-120m-1280ms",
        displayName: "Parakeet Realtime EOU 120M (1280ms)",
        repoFolderName: "parakeet-eou-streaming/1280ms",
        kind: .streamingASR,
        shortDescription: "Streaming ASR with 1280ms chunks — highest quality.",
        architecture: "Streaming FastConformer-TDT + EOU head",
        repository: "FluidInference/parakeet-realtime-eou-120m-coreml",
        revision: "40a23f4c0b333aa17ad8c0f2ea47ec2347f2f355",
        requiredRelativePaths: parakeetEouRequiredPaths,
        approximateSizeBytes: 224_525_706,
        engine: .parakeetEOU
    )

    // MARK: - Qwen3 ASR (Alibaba transformer ASR)
    //
    // 16-language multilingual transformer-based ASR (EN, ZH, JA, KO,
    // VI, TH, ID, MS, HI, AR, TR, RU, DE, FR, ES, multilingual). One
    // HuggingFace repo `qwen3-asr-0.6b-coreml` with two precision
    // variants under `f32/` and `int8/` subPaths. Drives
    // `Qwen3AsrManager` (separate from `AsrManager`) — adapter not
    // wired yet, downloads currently fail (interim).
    private static let qwen3AsrRequiredPaths = [
        "qwen3_asr_audio_encoder_v2.mlmodelc/coremldata.bin",
        "qwen3_asr_embedding.mlmodelc/coremldata.bin",
        "qwen3_asr_decoder_stateful.mlmodelc/coremldata.bin",
    ]

    public static let qwen3AsrF32 = ModelDescriptor(
        id: "qwen3-asr-0.6b-f32",
        displayName: "Qwen3 ASR 0.6B (f32)",
        repoFolderName: "qwen3-asr-0.6b/f32",
        kind: .asr,
        shortDescription: "Multilingual ASR (16 languages) — full precision.",
        architecture: "Qwen3 transformer ASR",
        repository: "FluidInference/qwen3-asr-0.6b-coreml",
        revision: "c081689ec58bcf29c2ef7c474ef78a164bda672b",
        requiredRelativePaths: qwen3AsrRequiredPaths,
        approximateSizeBytes: 1_569_667_932,
        engine: .qwen3ASR
    )

    public static let qwen3AsrInt8 = ModelDescriptor(
        id: "qwen3-asr-0.6b-int8",
        displayName: "Qwen3 ASR 0.6B (int8)",
        repoFolderName: "qwen3-asr-0.6b/int8",
        kind: .asr,
        shortDescription: "Multilingual ASR (16 languages) — int8 quantized.",
        architecture: "Qwen3 transformer ASR (int8)",
        repository: "FluidInference/qwen3-asr-0.6b-coreml",
        revision: "c081689ec58bcf29c2ef7c474ef78a164bda672b",
        requiredRelativePaths: qwen3AsrRequiredPaths,
        approximateSizeBytes: 974_722_368,
        engine: .qwen3ASR
    )

    // MARK: - Speaker diarization
    //
    // Pyannote segmentation + WeSpeaker-v2 embedding. FluidAudio's
    // online diarizer default. Drives `OfflineDiarizerManager` despite
    // the name — see FluidAudio's variant routing in
    // `getRequiredModelNames`. Adapter not wired (interim).
    public static let speakerDiarization = ModelDescriptor(
        id: "speaker-diarization",
        displayName: "Speaker Diarization",
        repoFolderName: "speaker-diarization",
        kind: .diarization,
        shortDescription: "Pyannote segmentation + WeSpeaker-v2 embedding.",
        architecture: "Pyannote 3.1 + WeSpeaker-v2",
        repository: "FluidInference/speaker-diarization-coreml",
        revision: "1ed7a662fdc7109e36d822db793ee6eebdaf8594",
        requiredRelativePaths: [
            "pyannote_segmentation.mlmodelc/coremldata.bin",
            "wespeaker_v2.mlmodelc/coremldata.bin",
        ],
        approximateSizeBytes: 13_720_676,
        engine: .diarization
    )

    public static let registeredModels: [ModelDescriptor] = [
        parakeetTDT06Bv2,
        parakeetTDTCTC110M,
        parakeetTDT06Bv3,
        parakeetEou160ms,
        parakeetEou320ms,
        parakeetEou1280ms,
        qwen3AsrF32,
        qwen3AsrInt8,
        speakerDiarization,
    ]

    public static let defaultActiveDescriptor = ActiveModelDescriptor(
        voiceModel: parakeetTDT06Bv2,
        aiModelID: nil
    )

    public static func descriptor(for id: String) -> ModelDescriptor? {
        registeredModels.first { $0.id == id }
    }
}
