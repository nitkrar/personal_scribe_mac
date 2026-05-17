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
        ),
        madeBy: "NVIDIA · FluidInference",
        worksWith: "English",
        goodFor: "General dictation, long-form transcription",
        license: "CC-BY-4.0"
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
        ),
        madeBy: "NVIDIA · FluidInference",
        worksWith: "English",
        goodFor: "Quick dictation, battery-conscious use",
        license: "CC-BY-4.0",
        // Hybrid TDT-CTC: FluidAudio loads the CTC head from a
        // separate repo at runtime. Without declaring this aux,
        // Download misses ~98MB the model needs and Delete leaves
        // those bytes stranded on disk.
        auxiliaryRepoFolderNames: ["parakeet-ctc-110m-coreml"]
    )

    public static let parakeetTDT06Bv3 = ModelDescriptor(
        id: "parakeet-tdt-0.6b-v3",
        displayName: "Parakeet TDT 0.6B v3",
        // `Repo.parakeet.folderName` — default rule strips `-coreml`
        // from `parakeet-tdt-0.6b-v3-coreml`.
        repoFolderName: "parakeet-tdt-0.6b-v3",
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
        ),
        madeBy: "NVIDIA · FluidInference",
        worksWith: "25 European languages",
        goodFor: "Multilingual dictation",
        license: "Apache 2.0"
    )

    // MARK: - WhisperKit ASR
    //
    // Argmax's CoreML Whisper bundles plus OpenAI tokenizer assets.
    // Stage A.5 keeps these rows in the catalog but hidden
    // (`isEnabled: false`) until the real adapter lands in Stage B.
    // `approximateSizeBytes` includes the bundle plus the tokenizer
    // support files we pre-stage under `<leaf>/tokenizer/`.
    private static let whisperKitTokenizerRequiredPaths = [
        "tokenizer/config.json",
        "tokenizer/tokenizer.json",
        "tokenizer/tokenizer_config.json",
        "tokenizer/vocab.json",
        "tokenizer/merges.txt",
        "tokenizer/added_tokens.json",
        "tokenizer/special_tokens_map.json",
        "tokenizer/normalizer.json",
    ]

    private static let whisperKitCommonRequiredPaths = [
        "AudioEncoder.mlmodelc/coremldata.bin",
        "MelSpectrogram.mlmodelc/coremldata.bin",
        "TextDecoder.mlmodelc/coremldata.bin",
        "config.json",
        "generation_config.json",
    ] + whisperKitTokenizerRequiredPaths

    private static let whisperKitTurboRequiredPaths = [
        "AudioEncoder.mlmodelc/coremldata.bin",
        "MelSpectrogram.mlmodelc/coremldata.bin",
        "TextDecoder.mlmodelc/coremldata.bin",
        "TextDecoderContextPrefill.mlmodelc/coremldata.bin",
        "config.json",
        "generation_config.json",
    ] + whisperKitTokenizerRequiredPaths

    public static let whisperKitTiny = ModelDescriptor(
        id: "whisperkit-tiny",
        displayName: "Whisper Tiny (WhisperKit)",
        repoFolderName: "openai_whisper-tiny",
        shortDescription: "Fastest Whisper option - tiny multilingual model, lowest accuracy.",
        architecture: "Whisper (WhisperKit runtime)",
        repository: "argmaxinc/whisperkit-coreml",
        // Decorative only for WhisperKit bundle descriptors today;
        // runtime loads by bundle leaf, not a pinned HF revision.
        revision: "main",
        requiredRelativePaths: whisperKitCommonRequiredPaths,
        // HF tree audit (2026-05-18): bundle + tokenizer support files.
        approximateSizeBytes: 80_819_412,
        isEnabled: false,
        engine: .whisperKit,
        madeBy: "OpenAI · Argmax",
        worksWith: "Multilingual (~99 languages)",
        goodFor: "Quick multilingual dictation, smoke tests, low-RAM Macs",
        license: "MIT (WhisperKit) + Apache 2.0 (Whisper weights)",
        tokenizerSource: "openai/whisper-tiny"
    )

    public static let whisperKitSmall216MB = ModelDescriptor(
        id: "whisperkit-small-216mb",
        displayName: "Whisper Small (WhisperKit, 216MB)",
        repoFolderName: "openai_whisper-small_216MB",
        shortDescription: "Balanced Whisper model - multilingual, smaller RAM than large v3.",
        architecture: "Whisper (WhisperKit runtime)",
        repository: "argmaxinc/whisperkit-coreml",
        revision: "main",
        requiredRelativePaths: whisperKitCommonRequiredPaths,
        approximateSizeBytes: 221_534_762,
        isEnabled: false,
        engine: .whisperKit,
        madeBy: "OpenAI · Argmax",
        worksWith: "Multilingual (~99 languages)",
        goodFor: "Multilingual dictation on everyday Apple Silicon Macs",
        license: "MIT (WhisperKit) + Apache 2.0 (Whisper weights)",
        tokenizerSource: "openai/whisper-small"
    )

    public static let whisperKitSmallEn217MB = ModelDescriptor(
        id: "whisperkit-small-en-217mb",
        displayName: "Whisper Small English (WhisperKit, 217MB)",
        repoFolderName: "openai_whisper-small.en_217MB",
        shortDescription: "English-only Whisper small - focused dictation at lower RAM.",
        architecture: "Whisper (WhisperKit runtime)",
        repository: "argmaxinc/whisperkit-coreml",
        revision: "main",
        requiredRelativePaths: whisperKitCommonRequiredPaths,
        approximateSizeBytes: 221_630_409,
        isEnabled: false,
        engine: .whisperKit,
        madeBy: "OpenAI · Argmax",
        worksWith: "English",
        goodFor: "English dictation when you prefer Whisper over Parakeet",
        license: "MIT (WhisperKit) + Apache 2.0 (Whisper weights)",
        tokenizerSource: "openai/whisper-small.en"
    )

    public static let whisperKitLargeV3626MB = ModelDescriptor(
        id: "whisperkit-large-v3-626mb",
        displayName: "Whisper Large v3 (WhisperKit, 626MB)",
        repoFolderName: "openai_whisper-large-v3-v20240930_626MB",
        shortDescription: "High-accuracy Whisper - multilingual large v3 for better quality.",
        architecture: "Whisper (WhisperKit runtime)",
        repository: "argmaxinc/whisperkit-coreml",
        revision: "main",
        requiredRelativePaths: whisperKitCommonRequiredPaths,
        approximateSizeBytes: 631_102_783,
        isEnabled: false,
        engine: .whisperKit,
        madeBy: "OpenAI · Argmax",
        worksWith: "Multilingual (~99 languages)",
        goodFor: "Higher-accuracy multilingual dictation",
        license: "MIT (WhisperKit) + Apache 2.0 (Whisper weights)",
        tokenizerSource: "openai/whisper-large-v3"
    )

    public static let whisperKitLargeV3Turbo632MB = ModelDescriptor(
        id: "whisperkit-large-v3-turbo-632mb",
        displayName: "Whisper Large v3 Turbo (WhisperKit, 632MB)",
        repoFolderName: "openai_whisper-large-v3-v20240930_turbo_632MB",
        shortDescription: "Large v3 Turbo - faster Whisper decode on M2 and later.",
        architecture: "Whisper (WhisperKit runtime)",
        repository: "argmaxinc/whisperkit-coreml",
        revision: "main",
        requiredRelativePaths: whisperKitTurboRequiredPaths,
        approximateSizeBytes: 650_053_458,
        isEnabled: false,
        engine: .whisperKit,
        madeBy: "OpenAI · Argmax",
        worksWith: "Multilingual (~99 languages)",
        goodFor: "Higher-accuracy multilingual dictation on M2+ with faster decode",
        license: "MIT (WhisperKit) + Apache 2.0 (Whisper weights)",
        tokenizerSource: "openai/whisper-large-v3",
        requiredChipFamily: .m2OrLater
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
        shortDescription: "Streaming ASR with 160ms chunks — lowest latency.",
        architecture: "Streaming FastConformer-TDT + EOU head",
        repository: "FluidInference/parakeet-realtime-eou-120m-coreml",
        revision: "40a23f4c0b333aa17ad8c0f2ea47ec2347f2f355",
        requiredRelativePaths: parakeetEouRequiredPaths,
        approximateSizeBytes: 224_047_838,
        engine: .parakeetEOU,
        madeBy: "NVIDIA · FluidInference",
        worksWith: "English",
        goodFor: "Streaming dictation, lowest latency",
        license: "CC-BY-4.0"
    )

    public static let parakeetEou320ms = ModelDescriptor(
        id: "parakeet-realtime-eou-120m-320ms",
        displayName: "Parakeet Realtime EOU 120M (320ms)",
        repoFolderName: "parakeet-eou-streaming/320ms",
        shortDescription: "Streaming ASR with 320ms chunks — balanced.",
        architecture: "Streaming FastConformer-TDT + EOU head",
        repository: "FluidInference/parakeet-realtime-eou-120m-coreml",
        revision: "40a23f4c0b333aa17ad8c0f2ea47ec2347f2f355",
        requiredRelativePaths: parakeetEouRequiredPaths,
        approximateSizeBytes: 224_238_270,
        engine: .parakeetEOU,
        madeBy: "NVIDIA · FluidInference",
        worksWith: "English",
        goodFor: "Streaming dictation, balanced latency",
        license: "CC-BY-4.0"
    )

    public static let parakeetEou1280ms = ModelDescriptor(
        id: "parakeet-realtime-eou-120m-1280ms",
        displayName: "Parakeet Realtime EOU 120M (1280ms)",
        repoFolderName: "parakeet-eou-streaming/1280ms",
        shortDescription: "Streaming ASR with 1280ms chunks — highest quality.",
        architecture: "Streaming FastConformer-TDT + EOU head",
        repository: "FluidInference/parakeet-realtime-eou-120m-coreml",
        revision: "40a23f4c0b333aa17ad8c0f2ea47ec2347f2f355",
        requiredRelativePaths: parakeetEouRequiredPaths,
        approximateSizeBytes: 224_525_706,
        engine: .parakeetEOU,
        madeBy: "NVIDIA · FluidInference",
        worksWith: "English",
        goodFor: "Streaming dictation, highest accuracy",
        license: "CC-BY-4.0"
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
        "qwen3_asr_decoder_stateful.mlmodelc/coremldata.bin",
        "qwen3_asr_embeddings.bin",
        "vocab.json",
    ]

    public static let qwen3AsrF32 = ModelDescriptor(
        id: "qwen3-asr-0.6b-f32",
        displayName: "Qwen3 ASR 0.6B (f32)",
        repoFolderName: "qwen3-asr-0.6b/f32",
        shortDescription: "Multilingual ASR (16 languages) — full precision.",
        architecture: "Qwen3 transformer ASR",
        repository: "FluidInference/qwen3-asr-0.6b-coreml",
        revision: "c081689ec58bcf29c2ef7c474ef78a164bda672b",
        requiredRelativePaths: qwen3AsrRequiredPaths,
        approximateSizeBytes: 1_569_667_932,
        isEnabled: false,
        engine: .qwen3ASR,
        madeBy: "Alibaba Qwen team · FluidInference",
        worksWith: "16 languages (multilingual)",
        goodFor: "Multilingual dictation, non-English content",
        license: "Apache 2.0"
    )

    public static let qwen3AsrInt8 = ModelDescriptor(
        id: "qwen3-asr-0.6b-int8",
        displayName: "Qwen3 ASR 0.6B (int8)",
        repoFolderName: "qwen3-asr-0.6b/int8",
        shortDescription: "Multilingual ASR (16 languages) — int8 quantized.",
        architecture: "Qwen3 transformer ASR (int8)",
        repository: "FluidInference/qwen3-asr-0.6b-coreml",
        revision: "c081689ec58bcf29c2ef7c474ef78a164bda672b",
        requiredRelativePaths: qwen3AsrRequiredPaths,
        approximateSizeBytes: 974_722_368,
        isEnabled: false,
        engine: .qwen3ASR,
        madeBy: "Alibaba Qwen team · FluidInference",
        worksWith: "16 languages (multilingual)",
        goodFor: "Multilingual dictation on lower-RAM devices",
        license: "Apache 2.0"
    )

    // MARK: - Speaker diarization
    //
    // FluidAudio's *offline* diarizer (`OfflineDiarizerManager`) — VBx
    // clustering pipeline with four CoreML stages plus a PLDA params
    // JSON. The adapter calls `DownloadUtils.downloadRepo(.diarizer,
    // variant: "offline", ...)`; that variant produces the file set
    // below, NOT pyannote/wespeaker (which is the online diarizer
    // shape). Source of truth for the path list is FluidAudio's
    // `ModelNames.OfflineDiarizer.requiredModels` — keep this in sync
    // when bumping FluidAudio.
    public static let speakerDiarization = ModelDescriptor(
        id: "speaker-diarization",
        displayName: "Speaker Diarization",
        repoFolderName: "speaker-diarization",
        shortDescription: "Offline VBx-clustering diarizer (segmentation + FBank + embedding).",
        architecture: "FluidAudio offline diarizer (VBx clustering)",
        repository: "FluidInference/speaker-diarization-coreml",
        revision: "1ed7a662fdc7109e36d822db793ee6eebdaf8594",
        requiredRelativePaths: [
            "Segmentation.mlmodelc/coremldata.bin",
            "FBank.mlmodelc/coremldata.bin",
            "Embedding.mlmodelc/coremldata.bin",
            "PldaRho.mlmodelc/coremldata.bin",
            "plda-parameters.json",
        ],
        // Measured on disk after `OfflineDiarizerManager.downloadIfNeeded`
        // (2026-04-29) — `du -k`: 21,816 KB.
        approximateSizeBytes: 22_339_584,
        engine: .diarization,
        madeBy: "FluidInference",
        worksWith: "Language-agnostic",
        goodFor: "Multi-speaker recordings, who-spoke-when",
        license: "MIT + Apache 2.0"
    )

    public static let registeredModels: [ModelDescriptor] = [
        parakeetTDT06Bv2,
        parakeetTDTCTC110M,
        parakeetTDT06Bv3,
        whisperKitTiny,
        whisperKitSmall216MB,
        whisperKitSmallEn217MB,
        whisperKitLargeV3626MB,
        whisperKitLargeV3Turbo632MB,
        parakeetEou160ms,
        parakeetEou320ms,
        parakeetEou1280ms,
        qwen3AsrF32,
        qwen3AsrInt8,
        speakerDiarization,
    ]
}
