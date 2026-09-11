# Multi-language voice model feasibility

## Recommendation

Split this from the Modes editor ticket.

The app-only schema work is manageable, but the literal backend goal is not uniform across models:

- Qwen3 batch supports a real per-call language hint in FluidAudio: `.build/checkouts/FluidAudio/Sources/FluidAudio/ASR/Qwen3/Qwen3AsrManager.swift:45-75,82-100`.
- Parakeet TDT batch does not expose any language or locale parameter in either `AsrManager` or `ASRConfig`; only model-version selection exists: `.build/checkouts/FluidAudio/Sources/FluidAudio/ASR/Parakeet/AsrManager.swift:318-355,432-457`, `.build/checkouts/FluidAudio/Sources/FluidAudio/ASR/Parakeet/AsrTypes.swift:5-37`, `.build/checkouts/FluidAudio/Sources/FluidAudio/ASR/Parakeet/AsrModels.swift:460-469`.
- Parakeet realtime/EOU streaming also has no language parameter; only chunk-size / variant selection exists: `.build/checkouts/FluidAudio/Sources/FluidAudio/ASR/Parakeet/Streaming/ParakeetModelVariant.swift:14-23,82-100`, `.build/checkouts/FluidAudio/Sources/FluidAudio/ASR/Parakeet/Streaming/EOU/StreamingEouAsrManager.swift:224-233,249-315,350-385,575-585`.
- Modes currently bind a `ModelKind`, not a specific `ModelDescriptor`, so a mode cannot say “use Qwen for Japanese, Parakeet for English”; the active descriptor is late-bound globally at session start: `Sources/PersonalScribeCore/WorkflowMode/ProcessorSpec.swift:5-11,25-29`, `Sources/PersonalScribeSession/WorkflowMode/RecipeBuilder.swift:4-10,52-70`.
- Qwen descriptors are disabled in PersonalScribe today, and `ActiveModelService.enabledModels()` filters out disabled descriptors, so the only currently enabled multilingual batch model is Parakeet v3, which would ignore the picker: `Sources/PersonalScribeCore/Models/Selection/BuiltInModelCatalog.swift:213-247`, `Sources/PersonalScribeSession/Models/Selection/ActiveModelService.swift:181-186`.

If the product needs a mode-level language field now, ship it as schema/UI metadata plus a Qwen-only plumbing follow-up. Do not promise a backend effect for Parakeet until upstream FluidAudio adds a language API.

## 1. API support

| Engine | Per-call language hint? | Exact API | Accepted values | Default | Load-time instead? |
|---|---|---|---|---|---|
| Parakeet TDT v3 batch | No | `AsrManager.transcribe(_ audioBuffer: AVAudioPCMBuffer, source: AudioSource = .microphone)`, `transcribe(_ url: URL, source: AudioSource = .system)`, `transcribe(_ audioSamples: [Float], source: AudioSource = .microphone)` in `.build/checkouts/FluidAudio/Sources/FluidAudio/ASR/Parakeet/AsrManager.swift:318-355,432-457` | None | n/a | Model family is selected at load/download time via `AsrModelVersion` / `downloadAndLoad(version:)`, but not language-specific: `.build/checkouts/FluidAudio/Sources/FluidAudio/ASR/Parakeet/AsrModels.swift:5-25,460-469`. |
| Qwen3 batch | Yes | `Qwen3AsrManager.transcribe(audioSamples: [Float], language: String? = nil, maxNewTokens: Int = 512)` and `transcribe(audioSamples: [Float], language: Qwen3AsrConfig.Language?, maxNewTokens: Int = 512)` in `.build/checkouts/FluidAudio/Sources/FluidAudio/ASR/Qwen3/Qwen3AsrManager.swift:45-68` | `String` overload accepts enum raw values or English names through `Qwen3AsrConfig.Language(from:)`: `.build/checkouts/FluidAudio/Sources/FluidAudio/ASR/Qwen3/Qwen3AsrConfig.swift:75-158`. The typed overload accepts `Qwen3AsrConfig.Language`. | `nil` = auto-detect: `.build/checkouts/FluidAudio/Sources/FluidAudio/ASR/Qwen3/Qwen3AsrManager.swift:82-90`. Unknown strings warn and fall back to auto-detect: same lines. | No. `loadModels(from:)` takes only directory + compute units; language is resolved during `transcribe` and then used to build prompt tokens: `.build/checkouts/FluidAudio/Sources/FluidAudio/ASR/Qwen3/Qwen3AsrManager.swift:31-35,82-100,248-257`. |
| Parakeet realtime / EOU streaming | No | The public streaming surface is `appendAudio`, `processBufferedAudio`, `finish`, `reset`, etc. in `.build/checkouts/FluidAudio/Sources/FluidAudio/ASR/Parakeet/Streaming/ParakeetModelVariant.swift:20-58`; concrete EOU methods are `loadModels(modelDir:)`, `process(audioBuffer:)`, and `finish()` in `.build/checkouts/FluidAudio/Sources/FluidAudio/ASR/Parakeet/Streaming/EOU/StreamingEouAsrManager.swift:249-315,355-385`. | None | n/a | Chunk size / variant is chosen at init/factory time, not language: `.build/checkouts/FluidAudio/Sources/FluidAudio/ASR/Parakeet/Streaming/ParakeetModelVariant.swift:63-100`, `.build/checkouts/FluidAudio/Sources/FluidAudio/ASR/Parakeet/Streaming/EOU/StreamingEouAsrManager.swift:224-233`. |

### What this means

- Qwen3 is the only adapter family where a mode-level language can change the actual FluidAudio decode call.
- For Parakeet v3, the only FluidAudio-side switch is model family (`v2` vs `v3` vs `tdtCtc110m`), not language.
- For streaming Parakeet, adding a `language` parameter to our app protocol today would be dead weight unless we want pure metadata for future models.

## 2. Supported languages

### Parakeet TDT v3

FluidAudio docs repeatedly describe Parakeet v3 as “25 European languages”: `.build/checkouts/FluidAudio/Documentation/Models.md:11-13`, `.build/checkouts/FluidAudio/Documentation/ASR/GettingStarted.md:5-7`, `.build/checkouts/FluidAudio/Documentation/API.md:204-207`.

The only concrete 25-language enumeration I found is the FluidInference model card frontmatter for `parakeet-tdt-0.6b-v3-coreml`, which lists:

- `en` English
- `es` Spanish
- `fr` French
- `de` German
- `bg` Bulgarian
- `hr` Croatian
- `cs` Czech
- `da` Danish
- `nl` Dutch
- `et` Estonian
- `fi` Finnish
- `el` Greek
- `hu` Hungarian
- `it` Italian
- `lv` Latvian
- `lt` Lithuanian
- `mt` Maltese
- `pl` Polish
- `pt` Portuguese
- `ro` Romanian
- `sk` Slovak
- `sl` Slovenian
- `sv` Swedish
- `ru` Russian
- `uk` Ukrainian

Source: `https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v3-coreml/raw/main/README.md` lines 4-29.

Important discrepancy:

- FluidAudio’s in-repo FLEURS benchmark map/table only enumerate 24 languages and omit Portuguese: `.build/checkouts/FluidAudio/Sources/FluidAudioCLI/Commands/ASR/Parakeet/SlidingWindow/FleursBenchmark.swift:14-46`, `.build/checkouts/FluidAudio/Documentation/Benchmarks.md:14-40`.
- I would not hard-code the Parakeet picker until that `pt` mismatch is resolved upstream or confirmed as a benchmark-harness omission.

### Qwen3 ASR

There are two conflicting stories in the current upstream artifacts:

1. The actual FluidAudio source and docs expose 30 concrete languages.
2. The FluidInference CoreML model card and PersonalScribe descriptors still advertise “16 languages”, but that metadata is not a clean picker list.

The authoritative FluidAudio code path is the source enum:

- `Qwen3AsrConfig.Language` defines 30 concrete cases: Chinese (`zh`), English (`en`), Cantonese (`yue`), Arabic (`ar`), German (`de`), French (`fr`), Spanish (`es`), Portuguese (`pt`), Indonesian (`id`), Italian (`it`), Korean (`ko`), Russian (`ru`), Thai (`th`), Vietnamese (`vi`), Japanese (`ja`), Turkish (`tr`), Hindi (`hi`), Malay (`ms`), Dutch (`nl`), Swedish (`sv`), Danish (`da`), Finnish (`fi`), Polish (`pl`), Czech (`cs`), Filipino (`fil`), Persian (`fa`), Greek (`el`), Hungarian (`hu`), Macedonian (`mk`), Romanian (`ro`): `.build/checkouts/FluidAudio/Sources/FluidAudio/ASR/Qwen3/Qwen3AsrConfig.swift:73-158`.
- FluidAudio docs and CLI help match that 30-language set: `.build/checkouts/FluidAudio/Documentation/ASR/Qwen3-ASR.md:23-49`, `.build/checkouts/FluidAudio/Sources/FluidAudioCLI/Commands/ASR/Qwen3/Qwen3TranscribeCommand.swift:138-150`.
- The benchmark harness also maps 30 FLEURS codes to those 30 enum values: `.build/checkouts/FluidAudio/Sources/FluidAudioCLI/Commands/ASR/Qwen3/Qwen3AsrBenchmark.swift:12-47`.

The “16 languages” metadata is weaker and inconsistent:

- The FluidInference CoreML model card frontmatter lists `en`, `zh`, `ja`, `ko`, `vi`, `th`, `id`, `ms`, `hi`, `ar`, `tr`, `ru`, `de`, `fr`, `es`, and a non-language placeholder `multilingual`: `https://huggingface.co/FluidInference/qwen3-asr-0.6b-coreml/raw/main/README.md` lines 4-20.
- PersonalScribe copies that summary into the descriptors as `worksWith: "16 languages (multilingual)"`: `Sources/PersonalScribeCore/Models/Selection/BuiltInModelCatalog.swift:213-247`.

Conclusion: I cannot confirm a concrete, source-backed 16-language picker set for Qwen3. The current FluidAudio implementation supports 30 concrete languages; the 16-language metadata looks stale or marketing-oriented, not structurally usable.

### Monolingual descriptors that should hide the picker

- Parakeet v2 is English-only in both FluidAudio docs and our descriptor metadata: `.build/checkouts/FluidAudio/Documentation/Models.md:11-12`, `Sources/PersonalScribeCore/Models/Selection/BuiltInModelCatalog.swift:27-56`.
- Parakeet TDT-CTC 110M is also English-only in our descriptor metadata: `Sources/PersonalScribeCore/Models/Selection/BuiltInModelCatalog.swift:62-98`.
- Parakeet EOU streaming descriptors are all marked English-only in PersonalScribe: `Sources/PersonalScribeCore/Models/Selection/BuiltInModelCatalog.swift:147-195`.

## 3. Required schema/protocol changes, ranked by blast radius

### 1. `ProcessorSpec` / `WorkflowMode` / `BoundRecipe` / `RecipeBuilder` (highest blast radius)

Today a processor only stores `ModelKind`; there is nowhere to persist a per-mode language:

- `ProcessorSpec` cases are currently `.transcriber(kind:)`, `.streamingTranscriber(kind:)`, and `.diarizedTurns(...)`: `Sources/PersonalScribeCore/WorkflowMode/ProcessorSpec.swift:25-83`.
- `BoundRecipe` stores only resolved adapter instances, not per-processor options: `Sources/PersonalScribeSession/WorkflowMode/BoundRecipe.swift:15-47`.
- `RecipeBuilder` resolves the active descriptor once and throws the raw adapter into `BoundRecipe`: `Sources/PersonalScribeSession/WorkflowMode/RecipeBuilder.swift:36-70`.

Minimal app-side shape:

- Add `language: String?` to `.transcriber(...)`.
- Add `language: String?` to `.diarizedTurns(...)` for the per-turn ASR leg.
- Do not add it to `.streamingTranscriber(...)` yet unless the product explicitly wants stored-but-unused metadata.
- Carry the resolved language into `BoundRecipe`, then pass it at transcribe time.

Important architectural note:

- Because `ProcessorSpec` intentionally stores `ModelKind`, not `ModelDescriptor.id`, a language-aware mode still cannot force Qwen for one mode and Parakeet for another. That is a separate schema/product decision, not just a language-plumbing change: `Sources/PersonalScribeCore/WorkflowMode/ProcessorSpec.swift:5-11`, `Sources/PersonalScribeSession/WorkflowMode/RecipeBuilder.swift:102-107`.

### 2. `Transcriber` protocol and call sites (high blast radius)

The batch protocol is currently audio-only:

- `Transcriber.transcribe(_ audio: PCMBuffer)` in `Sources/PersonalScribeCore/Transcription/Transcriber.swift:17-21`.
- The orchestrator calls it with no options: `Sources/PersonalScribeSession/Pipeline/Orchestrator/SessionPipelineOrchestrator.swift:624-644`.
- Diarized fusion also calls it with no options: `Sources/PersonalScribeSession/Pipeline/Processors/DiarizedTurnTranscriptionProcessor.swift:106-125`.

Recommended change:

- Extend batch ASR to `transcribe(_ audio: PCMBuffer, language: String?)` or, better, `transcribe(_ audio: PCMBuffer, options: TranscriptionOptions)` so this does not become a one-off protocol churn for a single field.
- Thread the bound recipe’s language through the orchestrator and the diarized-turn processor.

I would not change `StreamingTranscriber` yet:

- Its current surface is stream-only, with no session-options object: `Sources/PersonalScribeCore/Transcription/StreamingTranscriber.swift:19-26`.
- FluidAudio streaming has no language support anyway.
- If streaming language ever becomes real, a session-start options argument is cleaner than a per-chunk `language`.

### 3. `ModelDescriptor` and validation/UI metadata (medium blast radius)

Today the app only has a display string, not structured supported-language data:

- `ModelDescriptor` stores `worksWith: String?`: `Sources/PersonalScribeCore/Models/Selection/ModelDescriptor.swift:143-145,172-213`.
- The settings UI only renders that raw string in the popover: `Sources/PersonalScribeAppKit/Settings/ModelInfoPopoverPresenter.swift:183-190`.

Needed additions:

- Add `supportedLanguages: [String]?` or a stronger typed wrapper.
- Validate recipe language choices against the active descriptor’s supported set.
- Keep `worksWith` for human copy, but stop using it as the data source.

I would also add an explicit mapping layer:

- Qwen accepts raw ISO-ish codes / English names, not arbitrary BCP-47 tags: `.build/checkouts/FluidAudio/Sources/FluidAudio/ASR/Qwen3/Qwen3AsrConfig.swift:75-158`.
- Parakeet model-card metadata uses simple language codes, while the benchmark harness uses FLEURS dataset codes.
- Passing `fr-FR` or `en-GB` straight into `Qwen3AsrManager` will not parse today; unsupported strings silently fall back to auto-detect: `.build/checkouts/FluidAudio/Sources/FluidAudio/ASR/Qwen3/Qwen3AsrManager.swift:82-90`.

### 4. Adapter changes (mixed: small for Qwen, blocked for Parakeet)

Qwen path:

- `FluidAudioQwenManaging.transcribe(audioSamples: [Float])` and `LiveFluidAudioQwenManager.transcribe(audioSamples:)` need a `language` parameter: `Sources/PersonalScribeTranscription/Adapters/FluidAudioQwenTranscriberAdapter.swift:5-13,122-141,214-216`.
- The adapter can then call `Qwen3AsrManager.transcribe(audioSamples:language:)`: `.build/checkouts/FluidAudio/Sources/FluidAudio/ASR/Qwen3/Qwen3AsrManager.swift:45-68`.

Parakeet path:

- `FluidAudioParakeetManaging.transcribe(samples:)` currently forwards to `AsrManager.transcribe(samples, source: .microphone)`: `Sources/PersonalScribeTranscription/Adapters/FluidAudioParakeetTranscriberAdapter.swift:288-310,410-412`.
- There is nothing to plumb app-side until upstream FluidAudio adds a language-aware API.

Streaming path:

- `FluidAudioStreamingTranscriberAdapter` and `StreamingEouAsrManager` have no usable language seam today: `Sources/PersonalScribeTranscription/Adapters/FluidAudioStreamingTranscriberAdapter.swift:110-125`, `.build/checkouts/FluidAudio/Sources/FluidAudio/ASR/Parakeet/Streaming/EOU/StreamingEouAsrManager.swift:355-385`.

Diarizer:

- No language changes needed. `FluidAudioOfflineDiarizerAdapter` only produces speaker turns and never calls ASR with a language parameter: `Sources/PersonalScribeTranscription/Adapters/FluidAudioOfflineDiarizerAdapter.swift:111-137,202-209`.

### 5. Validation changes (small but necessary)

`WorkflowModeValidator` currently checks only pipeline shape and model-kind availability:

- `Sources/PersonalScribeCore/WorkflowMode/WorkflowModeValidator.swift:33-91`.

If language is persisted in recipes, add:

- language-present-on-supported-processor checks
- language-supported-by-active-descriptor checks
- possibly “language required for multilingual-only mode” checks if product wants that rule

## 4. Effort estimate

### Literal full scope from the prompt: `L` / blocked

Reason:

- App-side Qwen plumbing is straightforward.
- App-side Parakeet plumbing is impossible without upstream FluidAudio API changes.
- Current mode architecture also cannot pin model families per mode.

Breakdown for the app-side portion that is actually implementable:

- `0.25-0.5d`: add structured language metadata to descriptors, mapping tables, and validator wiring.
- `0.5-0.75d`: recipe schema changes (`ProcessorSpec`, `BoundRecipe`, `RecipeBuilder`, orchestrator, diarized-turn processor) plus Codable/test fallout.
- `0.25-0.5d`: Qwen adapter/live-manager plumbing and validation.
- `0.25d`: UI/editor integration and picker hiding rules.

If you narrow scope to “persist a mode language and make it affect Qwen when Qwen is the active model”, that is `M` (roughly 0.75-1.25 days). If you keep the requirement “works across all multilingual descriptors”, it is blocked on upstream Parakeet support and should be treated as `L`.

## 5. Blockers / unknowns

- Parakeet batch has no per-call or load-time language hint API in FluidAudio today: `.build/checkouts/FluidAudio/Sources/FluidAudio/ASR/Parakeet/AsrManager.swift:318-355,432-457`, `.build/checkouts/FluidAudio/Sources/FluidAudio/ASR/Parakeet/AsrTypes.swift:5-37`.
- Parakeet streaming has no language hint API either: `.build/checkouts/FluidAudio/Sources/FluidAudio/ASR/Parakeet/Streaming/ParakeetModelVariant.swift:20-58`, `.build/checkouts/FluidAudio/Sources/FluidAudio/ASR/Parakeet/Streaming/EOU/StreamingEouAsrManager.swift:355-385`.
- Parakeet v3 language coverage is internally inconsistent: docs/model card say 25, but the benchmark harness enumerates only 24 and omits Portuguese.
- Qwen language coverage is also internally inconsistent: source/docs say 30 concrete languages, but the CoreML model card and our descriptors still advertise “16 languages” and use `multilingual` as a placeholder, not a real picker value.
- Qwen is currently disabled in PersonalScribe, so the one backend that can use language hints is not user-facing today: `Sources/PersonalScribeCore/Models/Selection/BuiltInModelCatalog.swift:213-247`, `Sources/PersonalScribeSession/Models/Selection/ActiveModelService.swift:181-186`.
- Modes bind `ModelKind`, not descriptor id, so a language-aware mode still cannot choose a different model family than the globally active one: `Sources/PersonalScribeCore/WorkflowMode/ProcessorSpec.swift:5-11`, `Sources/PersonalScribeSession/WorkflowMode/RecipeBuilder.swift:102-107`.
- If the app adopts BCP-47 in recipes, an explicit mapper is required. Qwen’s parser accepts only the raw enum codes or English names and otherwise silently falls back to auto-detect: `.build/checkouts/FluidAudio/Sources/FluidAudio/ASR/Qwen3/Qwen3AsrConfig.swift:143-157`, `.build/checkouts/FluidAudio/Sources/FluidAudio/ASR/Qwen3/Qwen3AsrManager.swift:82-90`.

## 6. Recommendation in ticket terms

- Do not bundle “mode language affects all multilingual ASR backends” into the Modes editor ticket.
- If the editor needs to store/display language now, land the schema/UI piece separately with structured language metadata.
- Make Qwen language plumbing a focused follow-up after deciding whether Qwen should be enabled and whether modes are allowed to pick a specific model family.
- Open an upstream FluidAudio question for Parakeet v3/realtime language hints and for the Parakeet/Qwen language-list inconsistencies before hard-coding picker contents.
