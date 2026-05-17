import Foundation

public enum TranscriptionEngine: Sendable, Equatable {
    case parakeetTDT
    /// Streaming end-of-utterance ASR (parakeet-realtime-eou-120m,
    /// chunked encoder). Different manager class
    /// (`StreamingEouAsrManager`).
    case parakeetEOU
    /// Qwen3 0.6B ASR — multilingual transformer-based ASR. Different
    /// manager class (`Qwen3AsrManager`). Catalog includes both f32
    /// and int8 precision variants.
    case qwen3ASR
    /// Whisper via WhisperKit. Stage A scaffolds the engine and
    /// catalog metadata behind disabled descriptors; Stage B wires the
    /// real adapter.
    case whisperKit
    /// Speaker diarization (pyannote segmentation + WeSpeaker
    /// embedding). Different manager class
    /// (`OfflineDiarizerManager`).
    case diarization
    // The batch, streaming, and diarization engines below their
    // shipped adapters today. `.whisperKit` is introduced in #095's
    // Stage A behind disabled descriptors; Stage B swaps in the real
    // adapter.
}

/// Broad capability category for a registered model. Used by the
/// Settings UI to filter what's shown (e.g. AI Models tab today only
/// surfaces `.asr`). Extensible: streaming/EOU, VAD, diarization, and
/// TTS variants will land their own cases as we add transcriber
/// adapters for them.
public enum ModelKind: String, Sendable, Equatable, CaseIterable, Codable {
    case asr
    case streamingASR
    case vad
    case diarization
    case tts

    /// Whether this kind has a working transcriber adapter today. The
    /// AI Models tab filters non-enabled kinds out so users can't
    /// activate a row that would fail at download / runtime. Flip a
    /// case to `true` once the corresponding adapter lands (#078).
    public var isEnabled: Bool {
        switch self {
        case .asr, .streamingASR, .diarization: return true
        case .vad, .tts: return false
        }
    }

    /// Human-readable label used as the section header in the AI
    /// Models tab. Plural form because each section shows the list of
    /// models for that kind.
    public var displayName: String {
        switch self {
        case .asr: return "Voice models"
        case .streamingASR: return "Streaming ASR"
        case .vad: return "Voice activity detection"
        case .diarization: return "Diarization"
        case .tts: return "Text-to-speech"
        }
    }
}

/// Published benchmark metrics for a registered model. Sourced from
/// the vendor's model card (e.g. HuggingFace Open ASR leaderboard).
/// All fields optional so ad-hoc descriptors constructed by tests for
/// unrelated purposes don't have to declare benchmarks — the popover
/// hides missing-metric rows rather than inventing numbers.
///
/// `averageWER` and `rtfx` are the inputs to computed-relative
/// rankings — the Settings info popover sorts all registered models
/// by these fields to assign a "Fastest / Fast / Slow" (for RTFx) or
/// "High / Medium / Low" (for WER) bucket. No fixed thresholds — each
/// rank falls out of the registry.
public struct ModelPerformance: Sendable, Equatable, Codable {
    /// Average Word Error Rate across the HuggingFace Open ASR
    /// leaderboard's eight test sets. Lower is more accurate.
    public let averageWER: Double?

    /// Real-time factor on the HuggingFace Open ASR leaderboard
    /// (seconds of audio processed per wall-clock second, batch size
    /// 128, A100). Higher is faster.
    public let rtfx: Double?

    /// Total parameter count for reference. Not used for ranking — a
    /// 110M CTC model can be faster AND less accurate than a 600M TDT
    /// model, so parameter count isn't a reliable proxy for either
    /// axis on its own.
    public let parameterCount: Int?

    public init(
        averageWER: Double? = nil,
        rtfx: Double? = nil,
        parameterCount: Int? = nil
    ) {
        self.averageWER = averageWER
        self.rtfx = rtfx
        self.parameterCount = parameterCount
    }
}

public struct ModelDescriptor: Sendable, Equatable {
    public let id: String                  // "parakeet-tdt-0.6b-v2" — user-facing identity, persisted in UserDefaults
    public let displayName: String         // "Parakeet TDT 0.6B" — surfaces in Settings UI
    /// On-disk folder name. **Must equal FluidAudio's `Repo.folderName`**
    /// for the corresponding repo so FluidAudio's cache-hit short-circuit
    /// matches what we wrote. Drift here causes silent re-downloads.
    /// Source: `FluidAudio/Sources/FluidAudio/ModelNames.swift` `folderName` switch.
    public let repoFolderName: String
    /// Broad capability category — derived from `engine` per L2 of #078.
    /// Single source of truth: change the engine, the kind follows.
    public var kind: ModelKind { engine.kind }
    /// Descriptor-level rollout flag. Keeps a model in the registry for
    /// metadata/tests while hiding it from live selectors.
    public let isEnabled: Bool
    /// One-line inline description shown under `displayName` in the
    /// Settings → AI Models row. Keep ≤70 chars so it fits on one line
    /// at the default settings content width (620pt) without
    /// truncation. Empty is a hard error for registered models; tests
    /// pin this.
    public let shortDescription: String
    /// Human-readable architecture label shown in the info popover's
    /// "Architecture" row (e.g. "FastConformer-TDT", "Hybrid
    /// FastConformer-TDT-CTC"). Lives on the descriptor rather than
    /// the engine enum because the engine is an identifier, not a
    /// user-facing label.
    public let architecture: String
    public let repository: String          // HuggingFace repo, e.g. "FluidInference/parakeet-tdt-0.6b-v2-coreml"
    public let revision: String            // pinned commit SHA
    public let requiredRelativePaths: [String]  // artifacts inside the repo to fetch
    public let approximateSizeBytes: Int64 // for display and disk-space checks
    public let engine: TranscriptionEngine
    /// Published benchmarks (WER, RTFx, params). Defaults to an
    /// empty-field struct for ad-hoc test fixtures.
    public let performance: ModelPerformance

    // MARK: - Human-friendly popover metadata
    //
    // All optional — ad-hoc test fixtures don't need to declare them;
    // the info popover hides rows whose value is nil.

    /// Vendor / porter credit shown in the popover's "Made by" row.
    /// E.g. "NVIDIA · FluidInference".
    public let madeBy: String?

    /// Language or locale support shown in the "Works with" row.
    /// E.g. "English" or "25 European languages".
    public let worksWith: String?

    /// Primary use-case shown in the "Good for" row.
    /// E.g. "General dictation, long-form transcription".
    public let goodFor: String?

    /// SPDX license identifier shown in the "License" row.
    /// E.g. "CC-BY-4.0" or "Apache 2.0".
    public let license: String?

    /// Optional tokenizer repo id for runtimes whose model bundle
    /// does not ship tokenizer assets inline.
    public let tokenizerSource: String?

    /// Optional chip requirement for descriptors that should be
    /// hidden on older Apple Silicon.
    public let requiredChipFamily: ChipFamily?

    /// Companion repos this descriptor's runtime needs in addition to
    /// `repoFolderName`. Folder names match FluidAudio's `Repo.folderName`
    /// for the auxiliary repos.
    ///
    /// Today only the Parakeet TDT-CTC 110m hybrid declares one — its
    /// runtime loads the CTC head from `parakeet-ctc-110m-coreml`
    /// alongside the TDT bundle at `parakeet-tdt-ctc-110m`. Without
    /// declaring the auxiliary, "Download" misses ~98MB the model
    /// actually needs (FluidAudio fetches it implicitly on first
    /// activate) and "Delete" leaves that 98MB stranded.
    ///
    /// Provider iterates `repoFolderName + auxiliaryRepoFolderNames`
    /// for `removeDownloadedFiles`. The adapter's `downloadIfNeeded`
    /// pulls the auxiliaries in the same pass as the primary so all
    /// bytes a model needs land at Download time, not at Activate.
    public let auxiliaryRepoFolderNames: [String]

    public init(
        id: String,
        displayName: String,
        // `repoFolderName` defaults to `id` for ad-hoc test fixtures
        // and any historical caller — preserves the pre-#024.5
        // behavior where the on-disk folder equaled `id`. Catalog
        // entries should pass FluidAudio's `Repo.folderName`
        // explicitly.
        repoFolderName: String? = nil,
        shortDescription: String,
        architecture: String,
        repository: String,
        revision: String,
        requiredRelativePaths: [String],
        approximateSizeBytes: Int64,
        isEnabled: Bool = true,
        engine: TranscriptionEngine,
        performance: ModelPerformance = ModelPerformance(),
        madeBy: String? = nil,
        worksWith: String? = nil,
        goodFor: String? = nil,
        license: String? = nil,
        tokenizerSource: String? = nil,
        requiredChipFamily: ChipFamily? = nil,
        auxiliaryRepoFolderNames: [String] = []
    ) {
        self.id = id
        self.displayName = displayName
        self.repoFolderName = repoFolderName ?? id
        self.shortDescription = shortDescription
        self.architecture = architecture
        self.repository = repository
        self.revision = revision
        self.requiredRelativePaths = requiredRelativePaths
        self.approximateSizeBytes = approximateSizeBytes
        self.isEnabled = isEnabled
        self.engine = engine
        self.performance = performance
        self.madeBy = madeBy
        self.worksWith = worksWith
        self.goodFor = goodFor
        self.license = license
        self.tokenizerSource = tokenizerSource
        self.requiredChipFamily = requiredChipFamily
        self.auxiliaryRepoFolderNames = auxiliaryRepoFolderNames
    }

    public func resolveURL(for relativePath: String) -> URL {
        URL(
            string: "https://huggingface.co/\(repository)/resolve/\(revision)/\(relativePath)"
        )!
    }
}
