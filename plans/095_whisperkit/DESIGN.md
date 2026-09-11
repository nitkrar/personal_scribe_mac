# #095 — Whisper via WhisperKit — DESIGN (revision 3)

Status: locked (claude-atlas/slate, 2026-05-17). **This is revision 3** — supersedes revision 2 after codex-hermes' second-pass review (req-0001). Per the 2-pass review cap, this revision is the final design before implementation.

Revision history:
- rev 1 → adversarial review by codex-hermes (req-0116) + pool-codex-1 (req-0115) found 2 BLOCKERs + 6 HIGHs + 4 MEDIUMs + 2 LOWs. Captured at `REVIEW-consolidated.md`.
- rev 2 → folded all 14 concerns; sent for second-pass review.
- rev 3 (this) → folded 5 second-pass concerns from codex-hermes (req-0001): D4 download-path was still wrong (C1 BLOCKER), Stage A wasn't atomic (C2), chip-gating was incomplete (C3), test plan had leftover coupling (C4), manual verification missed the offline-pass scenario D5 was added to prevent (C5).

Scope: BACKLOG.md #095 "Extend ASR catalog beyond Parakeet+Qwen". Tier 2 (WhisperKit) only — Tier 3 reference notes in #095's body remain out of scope.

This document locks the (revised) design decisions. Step-by-step rollout lives in `IMPLEMENTATION.md` (to follow).

## What changed in revision 3

Five concerns from the second-pass review folded:

- **C1 (BLOCKER) — D4 still overclaimed.** `HubApi.snapshot` only takes `downloadBase:`, not an arbitrary destination. Revision 2 said "drive `HubApi.snapshot` directly into `<modelsRoot>/<repoFolderName>`" — that's not what the API does. Revision 3: explicit two-step **download → copy** sequence. Adapter calls `HubApi.snapshot(... downloadBase: <stagingRoot>)`, then `FileManager.moveItem` from the HF cache layout into our `<modelsRoot>/<repoFolderName>/` leaf. Cache leaf invariant preserved; download path is now actually implementable.
- **C2 (HIGH) — Stage A wasn't atomic.** Revision 2 added `fatalError("WhisperKitTranscriberAdapter not yet implemented")` to ModelBoundProcessorProvider while also enabling 5 Whisper descriptors in the catalog — meaning a user could activate a Whisper row mid-implementation and crash the app. Revision 3 splits descriptor introduction from descriptor enabling: Stage A lands descriptors with `isEnabled: false`; Stage B's final step flips them to `true` in the same commit that wires the real adapter.
- **C3 (MEDIUM) — chip-gating was UI-only.** Revision 2 only filtered `enabledModels(kind:)`. But `activeDescriptor(for:)`, `setActive`, and `resolveInitialActiveIDs` all bypass that filter and could end up with a disallowed descriptor active. Revision 3 centralizes the predicate in a new `ActiveModelService.canActivate(_:) -> Bool` helper, applied at all four call sites.
- **C4 (MEDIUM) — leftover unknown-id test.** Revision 2 carried a Whisper-specific `unknownVoiceModelID` test path inherited from the Parakeet adapter, but the new manager seam is descriptor-driven (no internal enum keyed by descriptor id). Revision 3 drops the test; replaces with descriptor-contract tests (non-empty `repoFolderName`, non-empty `tokenizerSource`, required paths). Adding future Whisper descriptors becomes additive.
- **C5 (MEDIUM) — manual verification missed offline pass.** D5 exists to eliminate first-activate network fetch; the test plan didn't actually exercise that. Revision 3 adds `MV-WHISPER-OFFLINE`: download with network on, disable network, activate + transcribe successfully. Also corrects the runbook filename from non-existent `ManualAIModelsVerification.md` to the real `ManualSettingsVerification.md`.

## What changed in revision 2 (preserved for traceability)

Two adversarial reviewers independently audited the WhisperKit source + HF catalog + our codebase and found:
- **D4 cache-path invariant was wrong.** `WhisperKitConfig.modelFolder` is `String?` not `URL`, and setting it makes `setupModels` skip download. The "WhisperKit drives download, our path wins" claim doesn't survive contact with the source.
- **Single-result `transcribe(audioArray:)` was assumed**, but real signature returns `[TranscriptionResult]` with no merge policy specified.
- **Tokenizer is NOT bundled** — fetched separately from `openai/whisper-*` on HF if local `tokenizer.json` is missing.
- **`whisper-tiny-en` was sized at ~75 MB**; actual is ~153 MB (bundle ships both `.mlmodelc` AND `.mlpackage`).
- **`isEnabled: true` for all six descriptors ignores device gating** — WhisperKit's config excludes turbo variants on M1.
- Token timings + log-prob confidence claims overstated.
- Several minor inventory corrections (package URL, macOS floor, validator semantics).

Revision 2 fixes all of these. Stage A.0 spike collapses to a confirmation pass against the already-verified findings rather than a discovery.

## 1. Goal

(Unchanged from revision 1.) Add Whisper to Ninimma's ASR catalog by integrating WhisperKit (Apple Silicon CoreML, ANE-accelerated, MIT) as a new transcription engine. Whisper unblocks multilingual transcription for non-European languages (Japanese, Chinese, Korean, Arabic, Vietnamese, Thai, Hindi, Indonesian, etc.) — coverage Parakeet does not provide and Qwen has not delivered (Qwen3 is `isEnabled: false` in catalog; see BACKLOG.md #091).

Non-goals (unchanged):
- Per-mode language hint plumbing (#091's scope; Whisper ships standalone with auto-detect).
- Tier 3 engines (Canary, Granite, Phi-4, SeamlessM4T, whisper.cpp).
- Real-time / streaming Whisper.
- Whisper × diarization fusion (composes for free; no extra work in #095).

## 2. Verified facts (replaces revision 1's "preconditions" table)

These are the audit-verified API facts that drive the revised decisions. Sources: `/tmp/req-0115-WhisperKit/Sources/WhisperKit/...` (cloned upstream HEAD) and HF tree API for `argmaxinc/whisperkit-coreml`.

### 2.1 WhisperKit API surface

| Symbol | Verified shape | Source |
|---|---|---|
| `WhisperKitConfig.modelFolder` | `String?` — when set, `setupModels` **skips download** | Configurations.swift:18-21,75-81; WhisperKit.swift:303-351 |
| `WhisperKit.download(variant:downloadBase:from:progressCallback:)` | downloads bundle to `<downloadBase>/models/argmaxinc/whisperkit-coreml/<bundle>/` — does NOT honor an arbitrary destination | WhisperKit.swift:244-295; HubApi.swift:350-352,580-584 |
| `HubApi.snapshot(from:matching:progressHandler:)` | low-level downloader; exposes `Progress`; can write to a controlled location | WhisperKit.swift HubApi vendored copy |
| `WhisperKit.transcribe(audioArray:decodeOptions:callback:segmentCallback:)` | `[Float] → async throws → [TranscriptionResult]` (array, not single) | WhisperKit.swift:867-930 |
| `loadTokenizerIfNeeded()` | searches local folders for `tokenizer.json`; falls back to fetching `openai/whisper-*` from HF if absent | WhisperKit.swift:462-480; ModelUtilities.swift:17-76,175-203 |
| `TranscriptionResult` | reference type, `@unchecked Sendable` (lock-backed); class `WhisperKit` itself is non-Sendable | Models.swift:441-447,574-640; multiple `@unchecked Sendable` in ArgmaxCore |
| Per-token text+start+end timings | **not exposed as a stable public surface**. Only per-**segment** start/end + optional `WordTiming` (when `wordTimestamps=true`) | Models.swift:574-640; SegmentSeeker.swift:340-407,528-603 |
| `avgLogProb`, `tokenLogProbs` | **log-probabilities** (negative-friendly), not probabilities. `exp(...)` needed to map to `[0,1]` | Models.swift:383-389,574-587,648; SegmentSeeker.swift:393-403 |
| macOS minimum | macOS 13 (our 14 floor is fine) | Package.swift:9-14 |
| External deps in `WhisperKit` target | `ArgmaxCore` (local) only. `swift-transformers`/Vapor only loaded for CLI when `BUILD_ALL` env set | Package.swift:41-49,66-70,116-130 |
| SPM package | `argmaxinc/argmax-oss-swift` (umbrella) exposes `WhisperKit` as a product. Standalone `argmaxinc/WhisperKit` repo shares HEAD today but should not be assumed permanent. Tags up to `v1.0.0`. | README.md:89-125 |

### 2.2 HF bundle inventory (revised)

| Bundle name | Exact size (bytes) | Notes |
|---|---|---|
| `openai_whisper-tiny` | 76,635,397 (~77 MB) | multilingual, clean bundle |
| `openai_whisper-tiny.en` | 152,992,804 (~153 MB) | ships both `.mlmodelc` + `.mlpackage` of each model — ~half is dead weight |
| `openai_whisper-small_216MB` | ~216 MB | multilingual, quantized |
| `openai_whisper-small.en_217MB` | ~217 MB | English-only, quantized |
| `openai_whisper-large-v3-v20240930_626MB` | ~626 MB | multilingual, quantized, M1-supported |
| `openai_whisper-large-v3-v20240930_turbo_632MB` | ~632 MB | multilingual, 4-bit quantized turbo — **excluded from WhisperKit's M1 supported list** |

Bundles contain `AudioEncoder.mlmodelc/`, `TextDecoder.mlmodelc/`, `MelSpectrogram.mlmodelc/`, plus `TextDecoderContextPrefill.mlmodelc/` on turbo variants, plus `config.json` + `generation_config.json`. **No `tokenizer.json` ships in any bundle.**

### 2.3 Ninimma codebase facts (revised)

| Claim | Verified state | File:line |
|---|---|---|
| `Transcriber.transcribe(_:)` takes `PCMBuffer`, no options | Confirmed | Transcriber.swift:11-22 |
| `BuiltInModelCatalog.registeredModels` auto-surfaces in AI Models tab | Confirmed — `AIModelsTab.swift:32` iterates `service.enabledModels(kind: .asr)`. Section headers come from `ModelKind.displayName`. | AIModelsTab.swift:32, 56-57 |
| `ModelKind.isEnabled` is `.asr`-only | **FALSE — corrected.** `.asr`, `.streamingASR`, and `.diarization` are all enabled today. Whisper is `.asr`; new descriptors slot under "Voice models" section without code changes. | ModelDescriptor.swift:36-44 |
| `modelArtifactsAreValid` semantics | Checks: required files exist; `coremldata.bin` size > 0; `*.json` first non-whitespace char is `{` or `[`. Does NOT parse JSON; does NOT verify `weight.bin`/`model.mlmodel`/`model.mil` etc. Fast tripwire, not a full integrity check. | ModelBoundProcessorProvider.swift:241-268 |
| `ModelBoundProcessorProvider.adapterFactory` exhaustive switch on `descriptor.engine` | Confirmed | ModelBoundProcessorProvider.swift:21-57 |
| `auxiliaryRepoFolderNames` field on descriptor (used by Parakeet TDT-CTC 110M for CTC head) | Confirmed | ModelDescriptor.swift:170-194 |
| `.revision` is honored by HF | **Decorative** for FluidAudio (`ModelRegistry.resolveModel` hard-codes `resolve/main/`, BACKLOG #036). WhisperKit also pulls `main` by default. Pin for forensics only. | — |
| `#091` per-mode language plumbing | **Open** — no `supportedLanguages: [String]?` on `ModelDescriptor`, no `TranscriptionOptions` arg. Whisper ships with auto-detect. | — |

## 3. Locked decisions (revised D1–D11)

### D1 — Engine case: `.whisperKit`

Renamed from `.whisper` to be consistent with the existing vendor-bound cases (`.parakeetTDT`, `.qwen3ASR`, `.parakeetEOU`). `TranscriptionEngine+Kind` maps `.whisperKit → .asr`. `TranscriptionEngine+Codable` adds `case whisperKit = "whisperKit"`. Switch sites that route on engine get the new branch (compiler-forced).

**Future-runtime question (raised by both reviewers):** if/when `whisper.cpp` or another Whisper runtime lands, it gets its own engine case (e.g. `.whisperCpp`) — same convention. The model family isn't the source of truth for routing; the runtime is. No migration needed.

### D2 — SPM dependency: `argmaxinc/argmax-oss-swift`, product `WhisperKit`

```swift
.package(url: "https://github.com/argmaxinc/argmax-oss-swift.git", exact: "1.0.0"),
```

```swift
.product(name: "WhisperKit", package: "argmax-oss-swift"),
```

Pin to the latest stable tag at impl time (currently `v1.0.0`). Added only to the `PersonalScribeTranscription` target. Does NOT pull in `TTSKit`, `SpeakerKit`, or `swift-transformers` external deps (those are CLI-only via `BUILD_ALL`).

Stage A.0 spike: confirm `v1.0.0` is still the appropriate pin at impl time; check for breaking changes since the audited HEAD (`/tmp/req-0115-WhisperKit` SHA `984ab42f` from 2026-05-17).

### D3 — Adapter: `Sources/PersonalScribeTranscription/Adapters/WhisperKitTranscriberAdapter.swift`

- Public actor `WhisperKitTranscriberAdapter: Transcriber`.
- Same shape as `FluidAudioParakeetTranscriberAdapter`: descriptor + `StorageLocator` injected; `prepare()`/`downloadIfNeeded()`/`cleanup()` from `ModelLifecycle`; `transcribe(_ audio: PCMBuffer) async throws -> TranscriptionResult`.
- Internal `WhisperKitManaging` protocol seam for testability.
- **Sendable boundary contract (NEW per C8):** all WhisperKit return values (`[TranscriptionResult]`, `WordTiming`, etc.) are immediately copied into PersonalScribe value types (`String`, `Duration`, `Float`, our `TokenTiming` if applicable) **inside the actor** before crossing the boundary. No WhisperKit reference types escape the adapter. A test asserts the adapter's `transcribe` return is fully value-typed.
- `progressBroadcaster = FluidAudioDownloadProgressBroadcaster()` — reuse as-is despite the name.

### D4 — Cache path strategy: **two-step download → copy** into our path (revised in rev3)

(Was rev1: "WhisperKit drives download, our path wins" — didn't work, `modelFolder` short-circuits download. Was rev2: "drive `HubApi.snapshot` into our path directly" — didn't work, `HubApi.snapshot` only takes `downloadBase:` and writes to `<downloadBase>/models/<repo-id>/...`, not an arbitrary destination.)

**Three-step download flow in adapter `downloadIfNeeded`:**

1. Use a staging directory: `<modelsRoot>/.staging/<descriptorID>/`. Call `HubApi.snapshot(from: HubApiWrapper.Repo(id: "argmaxinc/whisperkit-coreml"), matching: [<bundle-relative paths>], downloadBase: <stagingRoot>, progressHandler: ...)`. Files land at `<stagingRoot>/models/argmaxinc/whisperkit-coreml/<bundleName>/...` (the HF cache layout `localRepoLocation` returns; HubApi.swift:350-352,580-584).
2. Call `HubApi.snapshot` again for the tokenizer repo (`openai/whisper-*`) into the same staging root. Files land at `<stagingRoot>/models/openai/whisper-*/...`.
3. `FileManager.moveItem` (or `copyItem` + delete) from the staging HF-cache paths into our canonical leaf: bundle → `<modelsRoot>/<repoFolderName>/`, tokenizer → `<modelsRoot>/<repoFolderName>/tokenizer/`. Clean up staging root on success. On failure, clean up partial staging.

**Load flow in `prepare`:**

After `downloadIfNeeded()`, construct `WhisperKitConfig(model: <bundleName>, modelFolder: <modelsRoot>/<repoFolderName>, download: false)`. WhisperKit's `setupModels` honors `modelFolder` + `download: false` (loads from local files, no network).

**Progress aggregation:**

Two `HubApi.snapshot` calls each emit `Progress`. Bridge both into `FluidAudioDownloadProgressBroadcaster`. Use `descriptor.approximateSizeBytes` (which now includes tokenizer) as the denominator: weight = `bundleSizeBytes / totalSizeBytes` for the first call, remainder for the second. Move/copy step itself is instant (within same volume) — no progress emission needed; emit `.finished` once move completes.

**Why this is the right shape:**
- Preserves the existing `repoFolderName`-as-cache-anchor invariant (ModelDescriptor.swift:102-106, ModelBoundProcessorProvider.swift:228, etc.). `isDownloaded` / `removeDownloadedFiles` work without special-casing Whisper.
- Mirrors the FluidAudio adapter pattern (bypass the vendor's higher-level downloader, control the destination).
- Tokenizer is pre-staged at download time, not lazily on first activate.
- Move (vs copy) is atomic on same-volume; no disk-doubling during the operation.

**Alternatives rejected:**
- "Accept HF cache layout as canonical" — would require special-casing `repoFolderName` for Whisper, breaking the uniform leaf invariant `isDownloaded`/`removeDownloadedFiles` depend on. Asymmetric with FluidAudio.
- "Just `copyItem`" — wastes disk during transfer; non-atomic. `moveItem` on same-volume is rename → atomic.

**Failure modes handled:**
- Staging-dir creation fails → `.modelLoadFailure`, no partial state.
- First `snapshot` fails → clean up partial staging, `.modelLoadFailure`.
- Second `snapshot` fails → clean up partial staging (including the completed first one), `.modelLoadFailure`.
- `moveItem` fails (e.g., across volumes) → fall back to `copyItem` + `removeItem`, log warning; if that fails too, clean up staging, `.modelLoadFailure`.
- Move succeeds, cleanup of staging fails → log warning, but `downloadIfNeeded` returns success (model is usable; staging is just litter).

### D4 — (rev2 wording, retained for context — superseded by rev3 above)

### D5 — Tokenizer: first-class artifact, pre-staged at download time (NEW)

WhisperKit needs `tokenizer.json` (and tokenizer-related files). The HF bundle does NOT ship it; WhisperKit falls back to fetching from `openai/whisper-*` on first load if absent.

Adapter behavior:
- `downloadIfNeeded` resolves the descriptor's `tokenizerSource` (e.g. `openai/whisper-tiny`, `openai/whisper-tiny.en`, `openai/whisper-small`, `openai/whisper-small.en`, `openai/whisper-large-v3`) — added as a new descriptor field (D7.2).
- Drives a second `HubApi.snapshot(from: HubApiWrapper.Repo(id: tokenizerSource), matching: nil)` into `<modelsRoot>/<repoFolderName>/tokenizer/` via the D4 download→copy mechanism.
- Files copied into a `tokenizer/` subdir under the bundle leaf — declared in `requiredRelativePaths` so `modelArtifactsAreValid` / `removeDownloadedFiles` cover them.
- `prepare` constructs `WhisperKitConfig` passing **both** `modelFolder` AND `tokenizerFolder` explicitly:
  ```swift
  WhisperKitConfig(
      model: descriptor.repoFolderName,
      modelFolder: <modelsRoot>/<repoFolderName>.path,
      tokenizerFolder: <modelsRoot>/<repoFolderName>/tokenizer,
      download: false
  )
  ```
  **Stage A.0 confirmed (commit `ad6fda5`, see `whisperkit-api-notes.md`):** `modelFolder` alone does NOT discover `<leaf>/tokenizer/`. WhisperKit's `loadTokenizerIfNeeded` search path looks at `<modelFolder>`, `<modelFolder>/models/openai/whisper-*/`, and `<tokenizerFolder>` — not the plain subdir. Passing `tokenizerFolder` explicitly is the only path that works.

Disk accounting: the tokenizer adds ~few MB per descriptor (tokenizer JSON + vocab.bin + merges/tokens). `approximateSizeBytes` rolled up to include tokenizer estimate.

### D6 — Capabilities: ALL FOUR FLAGS FALSE for v1 (revised)

Was: tokenTimings + confidence ON. Both reviewers showed why that's wrong.

Revised:

```swift
public nonisolated let capabilities = TranscriberCapabilities(
    providesTokenTimings: false,
    providesConfidence: false,
    providesPerformanceMetrics: false,
    providesCustomVocabulary: false
)
```

Reasoning:
- **`providesTokenTimings: false`** — WhisperKit exposes per-segment start/end and optional per-`WordTiming`, but NOT per-token text+start+end matching our `TokenTiming` shape. Mapping word→token is a lossy guess. Surfacing word timings requires extending `TranscriberCapabilities` with a `providesWordTimings: Bool` flag and adding a `WordTiming` type to `PersonalScribeCore` — out of scope for #095, file a follow-up if dogfood needs it.
- **`providesConfidence: false`** — WhisperKit exposes `avgLogProb`/`tokenLogProbs` (log-probs, can be negative). Our `confidence` is `[0,1]`. The calibration `exp(avgLogProb)` is mathematically defensible but adds a tested mapping layer that's not load-bearing for v1. Add later if a UI consumer needs it.
- **`providesPerformanceMetrics: false`** — WhisperKit has internal timing but the surface is not stable.
- **`providesCustomVocabulary: false`** — Whisper has no CTC custom-vocab head. Permanent.

`TranscriptionResult` returned by the adapter still populates `text`, `audioDuration`, `processingDuration`. The capability flags govern what optional metadata the UI is told to expect.

### D7 — Catalog v1 (revised — vendor-clarified naming per rev3 user-direction)

**Naming convention locked:** all #095 catalog entries use the `whisperkit-*` prefix (not `whisper-*`). This makes the runtime identity unambiguous in user-facing surfaces (AI Models tab row id, persisted active-descriptor UserDefaults key, transcript history `modeId` lookups). The follow-up whisper.cpp adapter ticket (see BACKLOG draft below) will mint a parallel `whispercpp-*` catalog under the same naming convention. The Whisper *family* (the underlying weights) is referenced in `displayName` / `worksWith` for human copy — the `id` is runtime-bound.

| `id` | `repoFolderName` | `tokenizerSource` (D5) | Languages | Size | Default-active? | `isEnabled` |
|---|---|---|---|---|---|---|
| `whisperkit-tiny` | `openai_whisper-tiny` | `openai/whisper-tiny` | multilingual (~99) | 77 MB + tokenizer | no | yes |
| `whisperkit-small-216mb` | `openai_whisper-small_216MB` | `openai/whisper-small` | multilingual (~99) | 216 MB + tokenizer | no | yes |
| `whisperkit-small-en-217mb` | `openai_whisper-small.en_217MB` | `openai/whisper-small.en` | English-only | 217 MB + tokenizer | no | yes |
| `whisperkit-large-v3-626mb` | `openai_whisper-large-v3-v20240930_626MB` | `openai/whisper-large-v3` | multilingual (~99) | 626 MB + tokenizer | no | yes (all chips) |
| `whisperkit-large-v3-turbo-632mb` | `openai_whisper-large-v3-v20240930_turbo_632MB` | `openai/whisper-large-v3` | multilingual (~99) | 632 MB + tokenizer | no | **conditional — M2+** |

`displayName` examples (human copy):
- `whisperkit-tiny` → "Whisper Tiny (WhisperKit)"
- `whisperkit-large-v3-turbo-632mb` → "Whisper Large v3 Turbo (WhisperKit, 632MB)"

The "(WhisperKit)" suffix tells users they're picking the WhisperKit runtime variant. When the whisper.cpp follow-up lands, its descriptors render as "Whisper Tiny (whisper.cpp)" etc. — user sees both runtimes side-by-side in the AI Models tab and can pick whichever they want to test.

`repoFolderName` continues to match WhisperKit's HF bundle name verbatim (so our cache-leaf invariant works with the D4 download→copy flow). The bundle name happens to start with `openai_whisper-` because that's how argmax inc names the HF directory; we don't control that — only the descriptor `id` and `displayName` are ours.

**Removed from v1 (vs revision 1):**
- `whisperkit-tiny-en` — bundle is ~153 MB not ~75 MB (ships redundant `.mlpackage` siblings). Either drop or update size and accept the bloat. Drop is simpler — `whisperkit-tiny` covers fast multilingual; English speakers wanting tiny use Parakeet TDT-CTC 110M (227 MB, English-only, already shipped).

**Device-gating (NEW per C7, centralized per rev3 C3):** `whisperkit-large-v3-turbo-632mb` is excluded from WhisperKit's M1 supported list. Implementation: add `requiredChipFamily: ChipFamily?` to descriptor (nil = all chips). Apply the predicate at **all four call sites** in `ActiveModelService`, not only the UI-facing list:

1. `enabledModels(kind:)` — UI filter (AI Models tab).
2. `activeDescriptor(for:)` — runtime resolution used by `RecipeBuilder` (RecipeBuilder.swift:153-157,189-192).
3. `setActive(_:)` — guard against persisting an unsupported descriptor.
4. `resolveInitialActiveIDs(...)` — startup recovery; if the persisted active descriptor isn't supported on current chip, fall back to default per the existing recovery path.

Centralize via a new helper `ActiveModelService.canActivate(_ descriptor: ModelDescriptor) -> Bool` that combines `descriptor.isEnabled` AND chip-gating. All four sites call this. Chip detection injected via `chipFamily: () -> ChipFamily = ChipFamily.current` constructor param for testability.

`ChipFamily` enum: `case m1, m2OrLater`. Detection via `sysctlbyname("machdep.cpu.brand_string", ...)` — simple substring match (M1 vs M2/M3/M4+); helper lives in `PersonalScribeCore/Platform/ChipFamily.swift`. Tests pin both branches with stubbed chip detection.

**D7.1 alternative considered + rejected:** filtering only `enabledModels(kind:)` (rev2 shape). Hermes flagged that `setActive`, `activeDescriptor(for:)`, and `resolveInitialActiveIDs` all bypass the UI filter — a turbo descriptor that's persisted-active from a previous M2-Mac restore could end up active on M1, hit a runtime device-unsupported error, and the user has no way to recover via the hidden row in the UI. Centralized predicate fixes this.

**Other descriptors deferred** (same as revision 1): all non-quantized large bundles, medium, large-v2 family, distil-whisper. See §6.5.

**Default-active** stays Parakeet TDT 0.6B v2 (`BuiltInModelCatalog.defaultModelId`). Whisper is opt-in via AI Models tab "Activate".

### D8 — Multi-result merge policy (NEW per C2)

`WhisperKit.transcribe(audioArray:)` returns `[TranscriptionResult]`. The array reflects WhisperKit's internal windowing — for any audio length the array can be 1+ elements (chunked windows on long audio, or fallback alternatives on short).

Merge rules in adapter:
1. **Text**: `results.map(\.text).joined(separator: " ")`. (WhisperKit handles per-segment whitespace internally; concat-with-space is the safe default.)
2. **`audioDuration`**: from the input `PCMBuffer.duration`, not from WhisperKit's output (avoids drift between input window and output window).
3. **`processingDuration`**: measured wall-clock around the `transcribe(audioArray:)` call (same pattern as Parakeet adapter, FluidAudioParakeetTranscriberAdapter.swift:121-129).
4. **`text` empty fallback**: if `results.isEmpty` or all `.text` are blank, return `TranscriptionResult` with `text: ""` — same as Parakeet's empty-text path.

Optional metadata (`tokenTimings`, `confidence`, `performanceMetrics`, `ctcDetectedTerms`, `ctcAppliedTerms`) all nil for v1 per D6.

Test asserts: stub manager returns `[result1, result2]` → adapter returns single `TranscriptionResult` with text `"text1 text2"` and audioDuration from input.

### D9 — Failure mapping (unchanged from revision 1)

All WhisperKit errors → `PersonalScribeError.transcriptionFailure` (transcribe path) or `.modelLoadFailure` (prepare/download paths). Tokenizer-fetch failure during `downloadIfNeeded` → `.modelLoadFailure`. Consistent with Parakeet adapter.

### D10 — Logging discipline (unchanged from revision 1)

Adapter does NOT log transcribed text. Only descriptor `id`, error category, stage (prepare/download/transcribe) go to `PersonalScribeLogger`.

### D11 — Tests: real coverage, no mock-theater (revised per C9 + rev3 C4)

Adapter tests (`Tests/PersonalScribeTranscriptionTests/Adapters/WhisperKitTranscriberAdapterTests.swift`):
- `prepare` idempotent + in-flight task dedup + cleanup on failure (parity with Parakeet).
- `downloadIfNeeded` pulls BOTH bundle AND tokenizer into `<modelsRoot>/<repoFolderName>/` — stub manager records both calls; test asserts both happened in order. Test that staging dir is created + cleaned up on success.
- `downloadIfNeeded` cleanup-on-failure: bundle download succeeds, tokenizer download throws → staging is cleaned up; nothing under `<modelsRoot>/<repoFolderName>/` from this attempt.
- `downloadIfNeeded` failure throws `.modelLoadFailure` and clears in-flight state.
- `transcribe` happy path: stub returns `[result1, result2]` → adapter returns single `TranscriptionResult` with merged text.
- `transcribe` empty path: stub returns `[]` → adapter returns `text: ""`.
- `transcribe` failure throws `.transcriptionFailure`.
- `cleanup` releases manager and resets state.
- **Value-type boundary**: adapter's `transcribe` return is `TranscriptionResult` (value type); test asserts via `Mirror` that no field is a class reference.

**Dropped from rev2 (per C4):** the `unknownVoiceModelID` test. The Whisper adapter is descriptor-driven — it doesn't carry an internal enum keyed by descriptor id (Parakeet did, hence Parakeet had this test). Future Whisper descriptors should be additive without adapter changes; testing for a "known id list" couples adapter to catalog, defeating that.

**Replaced with: descriptor-contract tests** in `BuiltInModelCatalogTests` (below) — assert every `.whisperKit` descriptor satisfies the manager's input contract (non-empty `repoFolderName`, non-empty `tokenizerSource`, non-empty `requiredRelativePaths`). Catalog grows additively; adapter doesn't change.

Catalog tests (`Tests/PersonalScribeCoreTests/Models/BuiltInModelCatalogTests.swift` extension):
- For each of the 5 new descriptors: assert `engine == .whisperKit`, `kind == .asr`, non-empty `shortDescription`, non-empty `repoFolderName`, non-empty `tokenizerSource`, non-empty `requiredRelativePaths`.
- **Exact size pin** within ±5% per descriptor (catches the tiny-en class of bug). `whisperkit-large-v3-626mb` tolerates 595..657MB; `whisperkit-large-v3-turbo-632mb` tolerates 600..664MB; `whisperkit-small-216mb` tolerates 205..227MB; `whisperkit-small-en-217mb` tolerates 206..228MB; `whisperkit-tiny` tolerates 73..81MB.
- Exact `repoFolderName` pin matching HF bundle name (catches typos).
- Exact `tokenizerSource` pin.
- `requiredChipFamily` pin for `whisperkit-large-v3-turbo-632mb` (`.m2OrLater`); nil for the other four.

Engine routing test (`Tests/PersonalScribeSessionTests/Models/Selection/ModelBoundProcessorProviderTests.swift` extension):
- `.whisperKit` descriptor resolves to a `transcriber:`-populated `AdapterRecord`.

Chip-gating tests (`Tests/PersonalScribeSessionTests/Models/Selection/ActiveModelServiceTests.swift` extension) — per rev3 C3:
- `canActivate(descriptor)` returns false for `.m2OrLater` descriptor when chip stub reports `.m1`.
- `enabledModels(kind:)` hides the descriptor.
- `setActive(descriptor)` rejects (or routes through error path; pick at impl time) when chip mismatch.
- `activeDescriptor(for:)` returns nil (or falls back to default) when persisted active is no longer activatable on current chip.
- `resolveInitialActiveIDs` falls back to default when persisted ID's descriptor isn't activatable.

Manual verification (`Tests/ManualVerifications/ManualSettingsVerification.md` extension — corrected filename per rev3 C5):
- `MV-WHISPERKIT-1..5`: per descriptor — download → activate → record 10s English clip → confirm transcript matches expectation → confirm tokenizer files exist on disk under `tokenizer/` → delete → confirm both bundle + tokenizer bytes gone.
- **`MV-WHISPERKIT-OFFLINE` (NEW per rev3 C5):** download `whisperkit-tiny` with network on. Disable Wi-Fi + Ethernet (or use Little Snitch to block network for the app). Activate the descriptor. Trigger a recording. Confirm transcript appears without any network fetch. Re-enable network. This is the test that proves D5 (pre-staged tokenizer) actually works — if tokenizer were lazily fetched on first activate, this MV would fail.
- `MV-WHISPERKIT-CHIP-GATE`: on M1 hardware, confirm `whisperkit-large-v3-turbo-632mb` is hidden from AI Models tab. Restart app with that descriptor previously persisted-active (e.g., copy a UserDefaults plist from an M2 dev machine) → confirm app falls back to default, doesn't crash.
- `MV-WHISPERKIT-NON-ENGLISH`: activate `whisperkit-large-v3-626mb`. Speak 10s in Japanese (or any non-European language). Confirm transcript is in target language (auto-detect picks the right one).

## 4. Code surfaces touched (revised)

### `PersonalScribeCore`
- `Models/Selection/TranscriptionEngine` enum — add `case whisperKit`.
- `Models/Selection/TranscriptionEngine+Kind.swift` — add `.whisperKit → .asr`.
- `Models/Selection/TranscriptionEngine+Codable.swift` — add `.whisperKit` case (raw value `"whisperKit"`).
- `Models/Selection/ModelDescriptor.swift` — add `tokenizerSource: String?` (D5) + `requiredChipFamily: ChipFamily?` (D7.1) fields. Both optional/nil-default → all existing descriptors unaffected.
- `Models/Selection/BuiltInModelCatalog.swift` — add 5 new descriptors + extend `registeredModels`.
- `Models/Selection/ChipFamily.swift` (NEW) — `enum ChipFamily { case m1; case m2OrLater }` + a static `current()` detector using `sysctlbyname`.

### `PersonalScribeSession`
- `Models/Selection/ActiveModelService.swift` — **revised per rev3 C3**: add `canActivate(_ descriptor: ModelDescriptor) -> Bool` helper combining `descriptor.isEnabled` AND chip-gating. Apply at four call sites:
  - `enabledModels(kind:)` — UI filter.
  - `activeDescriptor(for:)` — runtime resolution.
  - `setActive(_:)` — guard against persisting unsupported descriptor.
  - `resolveInitialActiveIDs(...)` — startup recovery falls back to default if persisted ID isn't activatable on current chip.
  Inject chip detection via `chipFamily: () -> ChipFamily = ChipFamily.current` constructor param for testability.
- `Models/Selection/ModelBoundProcessorProvider.swift:21-57` — new `.whisperKit` branch returning `AdapterRecord(descriptorID:, transcriber: WhisperKitTranscriberAdapter(...))`. Compiler-forced.

### `PersonalScribeTranscription`
- New `Adapters/WhisperKitTranscriberAdapter.swift` (~300 LOC, mirroring Parakeet adapter shape + D8 merge logic + D5 tokenizer pre-stage).
- `Package.swift` — add `argmaxinc/argmax-oss-swift` SPM dep (D2).

### `PersonalScribeAppKit`
- No code changes. AI Models tab auto-surfaces. Info popover renders `worksWith` / `madeBy` / `license` as freeform strings (we populate). Computed-relative WER/RTFx ranks default-skip when descriptors don't ship `performance` metrics (Whisper descriptors won't for v1).

### Tests + docs
- See D11.

## 5. Architecture parallel (revised)

```
                       ┌──────────────────────────────┐
                       │  ModelBoundProcessorProvider │  (Session layer)
                       │   switch descriptor.engine   │
                       └──────┬──────┬──────┬──────┬──┘
                              │      │      │      │
                  .parakeetTDT│  .qwen3ASR  │.parakeetEOU
                              │      │      │  .diarization
                              │      │      │      │  .whisperKit (NEW)
                              ▼      ▼      ▼      ▼      ▼
              FluidAudioParakeet  Qwen   Streaming  Diarizer  WhisperKit (NEW)
                  Adapter        Adapter Adapter   Adapter   Adapter
                       │           │       │         │         │
                       ▼           ▼       ▼         ▼         ▼
              ┌─────────────────────────────────────────────┐
              │   FluidAudio package                                │
              │   argmax-oss-swift package (WhisperKit product)     │
              └─────────────────────────────────────────────┘
                       │
                       ▼
       <modelsRoot>/<repoFolderName>/                 ← descriptor-controlled (FluidAudio)
       <modelsRoot>/<repoFolderName>/                 ← descriptor-controlled (WhisperKit, via pre-stage)
       <modelsRoot>/<repoFolderName>/tokenizer/       ← Whisper tokenizer, also pre-staged
```

Identical-to-FluidAudio invariants preserved (D4 + D5 make this true):
- `descriptor.repoFolderName` is the cache-hit anchor.
- `FluidAudioDownloadProgressBroadcaster` is the progress stream source.
- `PersonalScribeError` mapping at the protocol boundary.
- `isDownloaded` / `removeDownloadedFiles` are descriptor-uniform — no special-casing.

What's different from FluidAudio:
- Vendor: `argmax-oss-swift` (WhisperKit product).
- Auxiliary repos: **tokenizer is the auxiliary** (declared via D5's `tokenizerSource`, not `auxiliaryRepoFolderNames`).
- Custom-vocabulary CTC: not supported.
- Capabilities: all four flags false in v1 (D6).
- Multi-result merge: required (D8).

## 6. Remaining risks (revised — most "unconfirmed" risks resolved by audit)

### 6.1 Stage A.0 spike — tokenizer-folder API confirmation

D5 assumes either (a) WhisperKit exposes a `tokenizerFolder:` config parameter we can point at our pre-staged path, OR (b) WhisperKit's default tokenizer-lookup search finds files at a predictable subdir. Reviewer dump confirms `loadTokenizerIfNeeded` searches local folders before falling back to HF download — exact search precedence not pinned in this DESIGN.

**Mitigation:** Stage A.0 spike (now narrower) verifies: where WhisperKit looks for `tokenizer.json` when `modelFolder` is set, and the exact filename/path expected. If the search misses our pre-staged location, the adapter copies the tokenizer files into whatever WhisperKit expects post-download. Worst case: a 10-line file-copy step in adapter `downloadIfNeeded`. Not a real risk; just an inventory step.

### 6.2 Progress aggregation across bundle + tokenizer downloads

D4/D5 = two `HubApi.snapshot` calls. Naive sequencing emits progress 0%→100% for bundle, then 0%→100% for tokenizer — bad UX. Adapter aggregates with `descriptor.approximateSizeBytes` as the denominator; tokenizer ≈ few MB vs bundle ≈ 100s of MB, so the "tokenizer-only" trailing 5% is unobtrusive.

### 6.3 Disk pressure with 5 new descriptors

Worst case if every descriptor downloaded: ~77 + 216 + 217 + 626 + 632 ≈ **1.77 GB** of Whisper bundles, plus ~50 MB of tokenizers ≈ **1.82 GB total**. Combined Parakeet (~1.17 GB) + Qwen if both variants (~2.54 GB) = ~5.5 GB worst case voice models on disk. #025 (disk-precheck) covers the broader UX.

### 6.4 Concurrency boundary verification (D3 contract)

D3 mandates that no WhisperKit reference type escapes the adapter. A test pins this. Risk: a future contributor adds a WhisperKit-typed field to our `TranscriptionResult` extension and breaks the contract silently. The Sendable-check test fails the suite if that happens.

### 6.5 Future descriptors (unchanged from revision 1, see §6.5 of revision 1 for full list)

Non-quantized large bundles (3 GB each), medium (1.5 GB), large-v2 family, distil-whisper, base/base.en — all deferred. Captured here so a follow-up doesn't re-research.

### 6.6 Future: real-time streaming Whisper (verified in rev3)

WhisperKit OSS ships a public mic-streaming actor: `AudioStreamTranscriber` (`Sources/WhisperKit/Core/Audio/AudioStreamTranscriber.swift`). Verified by source audit in req-0001:
- Public API: `startStreamTranscription() async throws` / `stopStreamTranscription()`. Only gate is mic permission (AudioStreamTranscriber.swift:43-88).
- No license-key / API-key / telemetry / Pro-model check in OSS sources.
- Argmax CLI `argmax-cli transcribe --stream` uses `WhisperKit(config) + AudioStreamTranscriber` with standard `argmaxinc/whisperkit-coreml/...` bundles (TranscribeCLI.swift:275-319; README.md:223-227).
- **Same model bundles power batch + streaming.** No separate "streaming model" concept. `AudioStreamTranscriber` reuses the same loaded `audioEncoder/featureExtractor/segmentSeeker/textDecoder/tokenizer` from the `WhisperKit` instance.
- Argmax Pro "Real-time Transcription" is a separate product layer (WebSocket server, Deepgram-compatible, paid) — not a gate on OSS streaming. Pro runtime can also consume OSS Whisper bundles per Argmax docs.

**Implication for ticket scope:** #095 batch work is NOT wasted if Ninimma later wants a Whisper streaming mode. The same `argmax-oss-swift` dependency, the same 5 catalog descriptors, and the same staged-files layout all flow through to a streaming adapter. The future ticket adds a `StreamingTranscriber`-conforming wrapper around `AudioStreamTranscriber`, parallel to how #056 wired `FluidAudioStreamingTranscriberAdapter` for Parakeet EOU.

**Latency reality:** `AudioStreamTranscriber.realtimeLoop` hard-waits for >1.0s of new audio before each decode and polls in 100ms intervals (AudioStreamTranscriber.swift:130-140). Expected first-hypothesis latency: **~1.1–1.5s** on the smallest multilingual bundle. **Materially slower than Parakeet EOU's sub-300ms live cursor in #056.** That means a future streaming-Whisper mode is a **different product positioning** (non-European-language users accepting higher latency for multilingual coverage) — NOT a Parakeet replacement.

**Decision:** stay with WhisperKit per this DESIGN. File a future ticket if/when dogfood demands multilingual streaming. The future ticket is additive — same engine, new adapter.

**Caveat:** verification was source-level only. Hermes' attempted `swift build` in the local WhisperKit checkout hit a manifest issue; runtime proof comes only when #095 ships and we integrate. If the OSS streaming path turns out broken at runtime (unlikely given CLI users it), this carve-out gets revisited.

### 6.7 Out of scope (unchanged from rev2)

## 7. Effort estimate (revised)

- Stage A.0 — narrower spike: confirm tokenizer-folder API + lock package pin: **0.1d** (was 0.25–0.5d before review)
- Stage A — package dep + engine case + ChipFamily + 5 descriptors + catalog + tokenizerSource field: **0.5d** (was 0.25d — more new types)
- Stage B — adapter (manager seam + live impl + pre-stage download + tokenizer pre-stage + merge logic): **1–1.5d** (similar to revision 1, slightly larger because of D5)
- Stage C — tests (adapter + catalog + provider + engine + chip-gating + size pins + merge + Sendable boundary): **0.75d** (more thorough than revision 1)
- Stage D — manual-verification + 1-2 dogfood passes per descriptor: **0.5d**
- Stage E — backlog body update + close-out: **0.1d**

**Total: M+ (~2.9–3.5d)** — slightly higher than revision 1's M+ (~2.3–3d) because of the extra tokenizer plumbing, chip-gating, and stronger tests. Trade-off is buying out the BLOCKER risks rather than discovering them in implementation.

## 8. Dependencies and blockers (revised)

**Blockers:** none.
- #078 (adapter layer) — shipped.
- #091 (per-mode language hint) — not a blocker; Whisper auto-detect.
- #025 (disk-space precheck) — not a blocker.
- #088 (narrow FluidAudio download wrapper) — open. D4's pre-stage approach using `HubApi.snapshot` directly is precedent-setting for #088's eventual shape.

**Unblocks** (same as revision 1):
- Multilingual dictation for non-European users (~85 languages).
- Whisper as fallback when Parakeet underperforms domain-specifically.
- #091's first meaningful consumer.
- #094 offline file transcription (Whisper adapter works for #094's file pipeline for free).
