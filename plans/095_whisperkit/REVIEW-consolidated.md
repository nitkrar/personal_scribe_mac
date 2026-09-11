# #095 — WhisperKit DESIGN.md — Consolidated Adversarial Review

Sources:
- **codex-hermes** (req-0116, message at 2026-05-17T22:13:07): 10 concerns
- **pool-codex-1** (req-0115 [cancelled], direct message id 1365 at 2026-05-17T22:15:05): 14 concerns

Verdict: 2 unique BLOCKERs, 6 unique HIGHs, 4 unique MEDIUMs, 2 LOWs. **DESIGN.md needs material revision before IMPLEMENTATION.md.** The two BLOCKERs converge on the same root cause: I deferred verification of WhisperKit's actual API surface to "Stage A.0 spike" but locked decisions D4 and D3/D7 against unverified claims. Both reviewers did the spike independently and found the same invariants are wrong.

## BLOCKERs (must fix before any further plan work)

### C1. D4 cache-path invariant is false. *(both reviewers)*
- **What I claimed:** `WhisperKitConfig(model:, modelFolder:<ourPath>, download:true)` lets WhisperKit drive download into our `<modelsRoot>/<repoFolderName>` leaf, parallel to FluidAudio's `DownloadUtils.downloadRepo(repo, to:<ourPath>, ...)`.
- **What's actually true:**
  - `WhisperKitConfig.modelFolder` is `String?`, not `URL` (Configurations.swift:18-21,75-81).
  - If `modelFolder` is set, `setupModels` **short-circuits and skips download** (WhisperKit.swift:303-351, esp. 313-316).
  - If `modelFolder` is nil, `WhisperKit.download(...)` returns the variant folder under `<downloadBase>/models/argmaxinc/whisperkit-coreml/<bundle>/...`, NOT our `<modelsRoot>/<repoFolderName>` (WhisperKit.swift:244-295; HubApi.swift:350-352,580-584).
- **Implication:** the `repoFolderName`-as-cache-anchor invariant in our descriptor system (ModelDescriptor.swift:102-106, ModelBoundProcessorProvider.swift:228, FluidAudioQwenTranscriberAdapter.swift:197-203) does NOT translate to WhisperKit out of the box.
- **Fix options (pick one in DESIGN revision):**
  - (a) **Pre-stage**: drive `HubApi.snapshot(from:matching:progressHandler:)` ourselves into `<modelsRoot>/<repoFolderName>`, then construct `WhisperKitConfig(model:, modelFolder:<that path>, download:false)`. Preserves `repoFolderName` invariant. More code.
  - (b) **Accept HF cache layout**: redesign `repoFolderName` for WhisperKit descriptors to encode the HF cache leaf shape. Less code; breaks the uniform leaf invariant that `isDownloaded`/`removeDownloadedFiles` depend on.
  - (c) **Hybrid**: let WhisperKit download to its cache, then move/symlink to our leaf in adapter `downloadIfNeeded`. Adds disk churn.

### C2. `transcribe(audioArray:decodeOptions:)` returns `[TranscriptionResult]`, not single. *(pool-codex-1)*
- **What I claimed:** Adapter calls `transcribe(audioArray:)` and returns a `TranscriptionResult` via our `Transcriber.transcribe(_:) -> PersonalScribeCore.TranscriptionResult` (single).
- **What's actually true:** Exact signature: `transcribe(audioArray: [Float], decodeOptions: DecodingOptions? = nil, callback: TranscriptionCallback? = nil, segmentCallback: SegmentDiscoveryCallback? = nil) async throws -> [TranscriptionResult]` (WhisperKit.swift:867-930).
- **Implication:** the adapter MUST define a merge policy across the array. Are these chunked-window results that need concatenation? Are they alternatives from temperature fallback? The DESIGN has no spec.
- **Fix:** specify merge semantics in DESIGN (likely: concatenate `.text`s, sum durations, choose strategy for `confidence`/`tokenTimings`); add an adapter test that pins the merge behavior.

## HIGHs (revise before locking decisions)

### C3. D3/D7 "self-contained bundle" is false — tokenizer fetched separately. *(both reviewers)*
- **What I claimed:** WhisperKit bundles are self-contained; no auxiliaries needed (D3 / D7 / DESIGN §5 "what's different: auxiliary repos: none").
- **What's actually true:** `loadTokenizerIfNeeded()` searches for local `tokenizer.json`, falls back to downloading from `openai/whisper-*` on HuggingFace if absent (WhisperKit.swift:462-480; ModelUtilities.swift:17-76,175-203). HF bundle tree probes confirmed no `tokenizer.json` ships in `argmaxinc/whisperkit-coreml/<bundle>/` — only model dirs + `config.json` + `generation_config.json`.
- **Implication:** every Whisper activation triggers a second network fetch; `removeDownloadedFiles` doesn't clean tokenizer bytes; offline first-run will fail; disk precheck under-counts.
- **Fix:** either pre-stage tokenizer files as first-class artifacts (extend `requiredRelativePaths` + a `tokenizerFolder` concept), OR explicitly call out the second network fetch + offline-failure mode in DESIGN with a contract for how delete/disk-accounting handles it.

### C4. D6 overstates token timings + logprobs/confidence. *(both reviewers, two facets)*
- **C4a (timing):** Ninimma's `TokenTiming` (TokenTiming.swift:3-21) requires per-**token** `start`/`end`. WhisperKit exposes per-**segment** start/end + optional `WordTiming` (Models.swift:574-640; SegmentSeeker.swift:340-407,528-603; TranscribeTask.swift:197-233). No stable per-token text+start+end surface.
- **C4b (confidence):** `TranscriptionResult.confidence` is documented `[0,1]` (TranscriptionResult.swift:27-33). WhisperKit's `avgLogProb`/`tokenLogProbs` are **log-probabilities** (can be negative; Models.swift:383-389,574-587,648). SegmentSeeker uses `exp(probability)` to recover word probabilities (SegmentSeeker.swift:393-403).
- **Fix:** set `providesTokenTimings: false` AND `providesConfidence: false` for v1 (simplest). OR specify exact calibration (`exp(avgLogProb)` for confidence, drop tokenTimings entirely) and write tests that pin the mapping. Add a follow-up task to surface word-timing as new metadata if dogfood demands.

### C5. D7 `whisper-tiny-en` size is wrong by ~2×. *(both reviewers, identical numbers)*
- HF tree query: `openai_whisper-tiny.en` total = **152,992,804 bytes** (~153 MB), not the ~75 MB I claimed. Bundle ships BOTH `.mlmodelc` AND `.mlpackage` copies of each model (AudioEncoder/MelSpectrogram/TextDecoder). `detectModelURL` prefers `.mlmodelc` (ArgmaxCore/ModelUtilities.swift:57-70), so ~half the bytes are dead weight on disk.
- For reference: `openai_whisper-tiny` (multilingual, no `.en`) = 76,635,397 bytes (~77 MB) — matches my claim.
- **Fix:** either drop `whisper-tiny-en` from v1, OR set `approximateSizeBytes: 152_992_804` and call out in `shortDescription` that the bundle contains redundant `.mlpackage` siblings.

### C6. D2 dependency target is misspecified. *(pool-codex-1; hermes confirms partial)*
- **What I claimed:** add `argmaxinc/WhisperKit` SPM dep, pin `0.13.x`.
- **What's actually true:** install docs point to `argmaxinc/argmax-oss-swift` with a `WhisperKit` product (README.md:89-125). Tags on the standalone `argmaxinc/WhisperKit` repo go up to `v1.0.0`. The two repos currently share HEAD but design shouldn't assume that's permanent.
- **Implication:** the SPM URL + product name in `Package.swift` matter; getting it wrong breaks the build.
- **Fix:** pick the canonical package URL (likely `argmaxinc/argmax-oss-swift`), specify the product (`WhisperKit`), pin a real version (likely `1.0.0` or whatever's latest stable at impl time).

### C7. `isEnabled: true` for all six ignores device gating. *(pool-codex-1)*
- WhisperKit's shipped `config.json` (`Tests/WhisperKitTests/Resources/config-v04.json:81-96` for M1 vs `:116-141` for M2/M3/M4) **excludes `openai_whisper-large-v3-v20240930_turbo_632MB` from M1's supported list** (and other turbo variants similarly). Ninimma supports macOS 14 → M1 is in scope.
- **Implication:** an M1 user who downloads turbo-632MB will hit a device-unsupported error at runtime.
- **Fix:** add a `supportedChips: Set<ChipFamily>?` (or similar) field to descriptor; AI Models tab + activation filter against current chip. OR (simpler v1): hide turbo descriptors on M1 by setting `isEnabled` to a function of detected chip. OR (simplest v1): drop turbo from v1 catalog and add it back in a follow-up when device gating exists.

### C8. Concurrency risk under-specified. *(both reviewers)*
- WhisperKit's `TranscriptionResult` is a **lock-backed reference type marked `@unchecked Sendable`** (Models.swift:441-447); `WhisperKit` class itself is non-Sendable. Multiple `@unchecked Sendable` / `nonisolated(unsafe)` hits in ArgmaxCore. Package opts into experimental strict concurrency (Package.swift:145-146).
- **Implication:** putting WhisperKit behind a Swift 6 actor (as DESIGN D3 specifies) is necessary but not sufficient. Reference types crossing the actor boundary without conversion to value types are a data-race hazard.
- **Fix:** add an explicit constraint to D3: "All WhisperKit return values are immediately copied into PersonalScribe value types (`String`, `Duration`, `Float`) inside the actor before crossing the boundary; no WhisperKit reference types escape the adapter." Add a test that asserts the adapter's return value is fully value-typed.

### C9. Test plan has mock-theater. *(both reviewers)*
- §4 catalog test proposes only `1 MB < size < 5 GB` — wouldn't have caught the C5 tiny-en mistake.
- Parity-with-existing-Parakeet stub tests won't catch array-result merging (C2), tokenizer side-downloads (C3), or capability mapping errors (C4).
- **Fix:** add to test plan:
  - Exact `repoFolderName` pin + tight `approximateSizeBytes` pin (within ±5%) per descriptor.
  - Adapter test for multi-result merge (stub returns `[r1, r2]` → adapter returns single merged result with concatenated text + correct duration sum).
  - Adapter test for missing-tokenizer offline failure path.
  - Adapter test for confidence/timing capability flags matching what the result actually populates.
  - Path test: after `downloadIfNeeded`, `isDownloaded(descriptor)` returns true; after `removeDownloadedFiles`, all bytes (including tokenizer) are gone.

## MEDIUMs (worth addressing in DESIGN revision)

### C10. §2 misstates `modelArtifactsAreValid`. *(both reviewers)*
- I claimed it "validates `coremldata.bin` size > 0 + JSON content".
- Actual code (ModelBoundProcessorProvider.swift:241-268) checks files exist, `coremldata.bin` size > 0, and `*.json` first non-whitespace char is `{` or `[` — does NOT parse JSON, does NOT verify `weight.bin` / `model.mlmodel` / `model.mil`.
- **Fix:** correct the prose. Validator is shallower than I implied. (Acceptable for our use — it's a fast tripwire, not a full integrity check — but the design shouldn't rely on it for Whisper-specific corruption detection.)

### C11. D1 naming rationale conflicts with chosen case. *(both reviewers, partial)*
- D1 says ".whisper" is vendor-bound, but the chosen string is family-level. Existing cases (`.parakeetTDT`, `.qwen3ASR`, `.parakeetEOU`) are backend-specific.
- **Fix:** either rename to `.whisperKit` (consistent with `.qwen3ASR`), OR explicitly state in D1 that we're switching to a family-level naming scheme (which then implies follow-up renames for the existing cases — out of scope for #095).
- **Question for user (pool-codex-1's C10):** want future `whisper.cpp` / other runtimes to share this case, or force migration later?

### C12. §2 silently aligns to outdated UI state. *(pool-codex-1)*
- I wrote "today only `.asr` is enabled" in the AI Models tab row. Actually `ModelKind.isEnabled` returns true for `.streamingASR` and `.diarization` too (ModelDescriptor.swift:36-44; AIModelsTab.swift:56-57). Tab is no longer ASR-only.
- **Fix:** update prose. The "zero AI Models tab code changes for Whisper" conclusion still holds.

### C13. §5 repeats the false `repoFolderName` cache-anchor claim. *(pool-codex-1)*
- Subordinate to C1, but worth tracking separately because the prose in DESIGN §5 ("Architecture parallel") states "`descriptor.repoFolderName` is the cache-hit anchor" as a Whisper invariant. It is NOT, per C1.
- **Fix:** rewrite §5 after C1 is resolved — make the real anchor explicit and tested.

## LOWs (housekeeping)

### C14. macOS deployment target is fine; binary-size risk overstated. *(both reviewers)*
- WhisperKit supports macOS 13+ (Package.swift:9-14). Our macOS 14 floor is fine.
- Normal WhisperKit target deps = local `ArgmaxCore` only. No external `swift-transformers` / Vapor unless `BUILD_ALL` enabled for CLI (Package.swift:41-49,66-70,116-130).
- **Fix:** delete or rewrite the relevant risk in §6.1 / §6.5 — current text chases a non-issue.

## Direct API answers (pool-codex-1, for DESIGN revision)

- `WhisperKitConfig.modelFolder`: exists but `String?`, not `URL`.
- Download progress: yes — `WhisperKit.download(... progressCallback:)` and `HubApi.snapshot(...)` both expose `Progress`.
- Exact transcribe signature: `transcribe(audioArray: [Float], decodeOptions: DecodingOptions? = nil, callback: TranscriptionCallback? = nil, segmentCallback: SegmentDiscoveryCallback? = nil) async throws -> [TranscriptionResult]`.
- Tokenizer fetch: separate fallback to `openai/whisper-*` on HF if no local `tokenizer.json` found.

## What this means for the plan

DESIGN.md as-locked is wrong in 2 BLOCKER-grade ways and 6 HIGH-grade ways. The Stage A.0 spike I deferred turns out to have been the most important step — both adversarial reviewers ran it for me and the locked decisions don't survive contact with the real WhisperKit source.

**Recommended next move:** revise DESIGN.md to fix C1 (pick a path-control strategy), C2 (multi-result merge spec), C3 (tokenizer plumbing), C4 (capability flags), C5 (correct sizes), C6 (real package URL), C7 (device gating), C8 (Sendable boundary), C9 (real tests). Then re-circulate the revised DESIGN to a single reviewer for verification before drafting IMPLEMENTATION.md.

Both reviewers should be thanked + resolved. pool-codex-1's req-0115 is already cancelled; codex-hermes' req-0116 should be resolved with a thank-you summary.
