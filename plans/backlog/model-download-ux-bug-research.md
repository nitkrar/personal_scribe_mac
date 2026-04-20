# Model-download UX bug — research synthesis + options

**Status:** research complete, awaiting user decision on path
**Inputs:** `plans/backlog/research-chunks/{A,B,C,D,E}-*.md` (5 parallel agent reports)

---

## Bug (user-observed)

On first launch, the pill shows `.downloading (NN%)` for a few seconds, then flips to `.loading` — while the real ~450 MB model weights are still being fetched. On relaunch with stubs on disk, the `.downloading` phase is skipped entirely and the pill sits on `.loading` for minutes.

---

## Verified root cause

1. `Sources/PersonalScribeCore/Models/Selection/BuiltInModelCatalog.swift:4-17` — `requiredRelativePaths` lists only 5 stub files (`*.mlmodelc/coremldata.bin` ×4 + `parakeet_vocab.json`). Total a few MB. Real weights (`weights/weight.bin`, `model.mil`, `analytics/*`) are NOT in the list.
2. `Sources/PersonalScribeTranscription/FluidAudioModelDownloader.swift:37-94` — `PrivateModelDownloader.ensureModelAvailable` iterates that list and emits `.downloading` with `fractionCompleted = index / total` (file-count, not bytes). Finishes in seconds.
3. `Sources/PersonalScribeTranscription/Models/Selection/ModelAwareFluidAudioTranscriber.swift:221-227` — `.loading` is emitted as soon as `ensureValidDownloadedModel` returns.
4. `Sources/PersonalScribeTranscription/Models/Selection/ModelAwareFluidAudioInferenceClient.swift:28-32` — `AsrModels.load(from:version:)` is called with **no progress handler**. Inside FluidAudio 0.13.6:
   - `DownloadUtils.loadModelsOnce` sees `.mlmodelc` dirs exist → skips `downloadRepo` → `MLModel(contentsOf:)` at `DownloadUtils.swift:253` throws (weights missing).
   - `DownloadUtils.loadModels` wrapper catches, `rm -rf`s the repo dir, reruns once (`DownloadUtils.swift:127-143`).
   - Second pass: `allModelsExist == false` → `downloadRepo` pulls full ~450 MB from `huggingface.co/<repo>/resolve/main/<path>` (`DownloadUtils.swift:268-476`, `ModelRegistry.swift:56-62`).
5. Net: short `.downloading` (stubs) → long `.loading` (silent FluidAudio real-payload fetch).

### Secondary bugs surfaced during research

- **Stub-permissive validator.** `ModelArtifactStaging.modelArtifactsAreValid` (`ModelArtifactStaging.swift:37-71`) only checks that `coremldata.bin` is non-empty and vocab parses. Duplicate at `ModelAwareFluidAudioTranscriber.swift:328-359` (byte-identical drift, cosmetic only). Weight files never checked. On relaunch, stubs-only state passes → our downloader is skipped entirely → `.downloading` never emitted, straight to `.loading`.
- **Revision pin ignored.** `BuiltInModelCatalog.parakeetTDT06Bv2` pins `revision: "ee09c569..."` but FluidAudio's `ModelRegistry.resolveModel` hard-codes `resolve/main/`. Our pin is ignored on every silent redownload.
- **Fraction by file count, not bytes.** Even in the best-case with the right file list, our `PrivateModelDownloader` computes `(Double(index) + fileFraction) / Double(count)` — a vocab.json jumps the bar by 20 % while the encoder stays pinned for minutes (`FluidAudioModelDownloader.swift:66-89`).
- **Settings-triggered silent download.** `DefaultModelService.setActive` (`Sources/PersonalScribeSession/Models/Selection/DefaultModelService.swift:78-87`) calls `download(canonical.voiceModel) { _ in }` with a **no-op progress handler**. Switching models via Modes tab triggers a ~450 MB silent fetch with zero UI feedback — `SessionCoordinator` only subscribes to progress during active recording.
- **Session-start race.** `SessionPipelineOrchestrator.startRecording:186,453-466` calls `prepareTranscriberInBackground()` *after* publishing `.recording`. If prepare hasn't happened yet (weak eager prefetch — `AppStartupCoordinator:34-64` runs with `.background` priority), recording starts while download/load is in flight; stop flips to `.transcribing` → pill sits on `.loading` for minutes.
- **AIModelsTab is inert.** `Sources/PersonalScribeAppKit/Settings/AIModelsTab.swift:16-48` hardcodes `.ready`, ignores real disk state. Cannot regress because it doesn't show anything real.
- **`approximateSizeBytes` never read.** No disk-space precheck anywhere.

---

## Whisper.cpp / multilingual question (directly answered)

**User's recollection** — "we added our own downloader for multilingual / whisper.cpp" — **is not supported by the written record.**

- **Docs (Agent B):** no plan ties the downloader to whisper.cpp. Written motivation: multi-Parakeet-variant support + configurable models dir (`plans/SPEC_model_registry_and_base_dir.md:9`, `plans/PLAN_PHASES.md:133`, `plans/CENTRAL_LAYERS_PROMPT.md:296-307`). The multi-engine swap protocol was **explicitly rejected** before the downloader was written: `DECISIONS.md:51`, `REVIEW.md:371` ("Kill the engine swap"), `REVIEW_SYNTHESIS.md:70-172`.
- **Git (Agent C):** 11 commits touched the downloader; zero mention whisper / ggml / gguf / multilingual / engine-agnostic. Every commit frames it as a FluidAudio/Parakeet helper.
- **Code (Agent C, E):** `PrivateModelDownloader` is HF-bound (via `ModelDescriptor.resolveURL`'s final `https://huggingface.co/...` template, `ModelDescriptor.swift:36-40`). `ModelArtifactStaging` is CoreML-bound (`parakeet_vocab.json` magic-byte check). `TranscriptionEngine` enum has one case (`.parakeetTDT`) and is never read. A whisper.cpp engine would need its own downloader + validator + descriptor shape regardless.

**Conclusion:** keeping `PrivateModelDownloader` does not preserve a future whisper.cpp path. Deleting it does not block one.

---

## Re-ranked options

### Option 1 — Delete `PrivateModelDownloader`; wire FluidAudio's progress hook end-to-end ⭐

Hand the download entirely to FluidAudio. Pass a `DownloadUtils.ProgressHandler` into both `AsrModels.load(from:version:progressHandler:)` callsites (`ModelAwareFluidAudioInferenceClient.swift:28-31`, `FluidAudioInferenceClient.swift:32-35`). Map FluidAudio's phases (`.listing`, `.downloading(completedFiles:totalFiles:)`, `.compiling(modelName:)`) onto our `ModelDownloadProgress`. Delete `PrivateModelDownloader`, the pre-download step in both `performPrepare` paths, and the stub-permissive `modelArtifactsAreValid` duplicates.

**Pros**
- Eliminates the root cause — one downloader, byte-level progress, phase-aware.
- Fixes the "relaunch with stubs" second variant automatically (no stubs, no false-valid state).
- Fixes the race between phase emission and actual bytes moving.
- FluidAudio's progress hook is already byte-level via `downloadWithProgress` (`DownloadUtils.swift:489-509`).
- Smaller surface — less code to maintain.

**Cons / things to verify before committing**
- Revision pin: FluidAudio hard-codes `resolve/main/`. Our current pin is already non-functional in the silent-redownload path, so this is documenting reality rather than regressing. Surface it in `BACKLOG.md` as a known limitation.
- Configurable base dir: confirm `AsrModels.load(from: directory, ...)` actually uses our passed directory as the root (Agent A indicates yes — it's the `repoPath` argument).
- Multi-Parakeet-variant: FluidAudio's `asrModelVersion` covers this (already wired via `FluidAudioRuntimeVariant`).
- Tests: 3 tests + 1 shared fixture pin current-buggy behavior; they need updating or deleting (Agent D).

**Blast radius:** low. Agent E confirms phase-enum is only consumed by `AppStore.derivePillVisibility` + `MenuBarSceneModel.preparationProgress` (non-branching).

### Option 2 — Enumerate full file manifest in `requiredRelativePaths`

Walk the HuggingFace repo tree for each `.mlmodelc` and list every file (coremldata.bin + model.mil + weights/weight.bin + metadata.json + analytics/* + …). Keep ownership of download logic.

**Pros**
- Preserves the revision pin (our downloader uses `ModelDescriptor.resolveURL`).
- Keeps descriptor-driven config.

**Cons**
- Brittle to CoreML internal layout — every model variant needs its manifest re-enumerated; a new FluidAudio release could change `.mlmodelc` internals.
- Duplicates FluidAudio's own `ModelRegistry.fetchRepoFileList`.
- Still needs the validator fix (weight files must be checked).
- Still needs byte-based fraction math.
- Does not fix the `DefaultModelService.setActive` silent-download path.
- Does not fix the session-start race.
- Fraction-by-file-count → byte-based is a separate change.

**Verdict:** more code for an inferior outcome.

### Option 3 — Byte progress + defer `.loading` flip only

**Verdict: non-starter on its own.** The root cause is that our downloader doesn't fetch the weights at all. Byte-accurate progress on the stubs still finishes at 100 % in seconds; FluidAudio still silently downloads the real payload. Only viable stacked onto Option 2, at which point Option 2's costs apply.

---

## Recommended path

**Option 1, bundled with three targeted fixes.** Each is a small additional commit:

1. **Delete `PrivateModelDownloader` + stub-permissive validator.** Wire `DownloadUtils.ProgressHandler` into `ModelAwareFluidAudioInferenceClient.loadModel` and `FluidAudioInferenceClient.loadModel`. Map FluidAudio phases → our `ModelDownloadProgress`. Simplify `performPrepare` in both transcribers to `load model → load engine → finished` (no pre-download step; FluidAudio handles it).
2. **Fix `DefaultModelService.setActive` silent download.** Replace the `{ _ in }` no-op handler with a forward to a service-owned progress stream that Settings/AIModelsTab can subscribe to. Surface progress in AIModelsTab (which is currently inert and safe to enrich).
3. **Fix the session-start race.** Gate `.recording` publication on "model is ready" (or expose a distinct pill state, e.g. keep `.loading` visible until prepare completes *before* flipping to `.recording`). This is a small change in `SessionPipelineOrchestrator.startRecording:186` ordering.

Commits in separate logical steps so each can be reviewed / reverted independently.

---

## Test strategy

**Tests that pin current buggy behavior (will need deletion or retargeting)**
- `Tests/PersonalScribeTranscriptionTests/ModelDownloadProgressTests.swift:74-102` — `testPrepareOnCachedModelEmitsLoadingWithoutDownloading`
- `Tests/PersonalScribeTranscriptionTests/FluidAudioTranscriberAlreadyDownloadedTests.swift:43-55` — `testPrepareSkipsDownloadWhenModelAlreadyOnDisk`
- `Tests/PersonalScribeTranscriptionTests/ModelIntegrityTests.swift:6-17` — `testCorruptDownloadRetriesOnceThenSucceeds`
- `Tests/PersonalScribeTranscriptionTests/Support/TranscriptionTestSupport.swift:7-27` — `TestModelArtifacts.writeValid` fixture (largest radius — every test assuming "post-writeValid = valid" inherits stub-permissiveness)

**New failing tests to write first (per TDD discipline)**
- `testPhaseStreamReflectsRealBytes`: fake `AsrModels.load` that emits `.downloading(0..1 in chunks)`, assert pill state transitions `hidden → downloading(N%) → loading → idle`. No silent gap.
- `testRelaunchWithPartialModelResumesWithDownloadingPhase`: pre-seed a stubs-only directory, call prepare, assert `.downloading` emits before `.loading`.
- `testDefaultModelServiceSetActiveForwardsProgress`: inject fake downloader, assert progress visible on a service stream (not `{ _ in }`).
- `testStartRecordingDefersRecordingPublishedUntilModelReady`: fake prepare that takes > 500ms, assert pill shows `.loading` before any `.recording`.

**Fix-compatible tests (no change needed)**
8 transcription tests + `PillOverlayViewModelTests`, `PillOverlayPillAppearanceTests`, `AppStoreTests`.

**Manual verification checklist** (add to `Tests/PersonalScribeTranscriptionTests/ManualTranscriptionVerification.md`)
- First launch with empty models dir → pill shows `.downloading 0% → 100%` with moving progress bar over real wall-clock time, then briefly `.loading`, then idle.
- Relaunch after first install → pill stays idle (model already on disk). No spurious `.loading`.
- Change model in Modes tab when target model is not downloaded → Settings shows progress; pill may also show if app is foreground.

---

## Decisions (2026-04-21)

1. **Revision pinning:** accept `main` as the de-facto pin. FluidAudio's `ModelRegistry.resolveModel` hard-codes `resolve/main/`; our `revision` field stays (decorative) for now, documented in `BACKLOG.md`. No FluidAudio PR.
2. **Phasing:** land now — do NOT wait for Phase 4 (Command Mode). Phase 4 will introduce a separate LLM downloader, sharing only the existing `ModelDownloadProgress` type in `PersonalScribeCore`. No premature `ModelDownloadService` abstraction.
3. **Settings surface:** AIModelsTab = authoritative. Per-model state (not-downloaded / downloading / ready / failed), disk usage, download / delete / active-switch. Section headers (`Voice models`, later `AI models`) so LLM rows slot in without redesign. Modes tab shows compact status summary only.
4. **Hotkey during download: record-without-transcribe.** Capture proceeds, pipeline pauses at transcription stage; transcription triggers when model reaches `.finished`. User feedback via live-updating ResponseCard ("Recording — transcribing when model is ready (NN%)"). Extend `ResponseCard.show(text:above:autoDismissAfter:)` with an `update(text:)` method; pause auto-dismiss while recording is in flight.

---

## Reference audit

- `PROPOSAL.md:59,152,195,212,318` — whisper.cpp parked as "v0.2+ / Future" non-English fallback (B).
- `DECISIONS.md:9,51` — multi-engine swap explicitly rejected before downloader landed (B).
- `BACKLOG.md:224,240` — whisper.cpp as a separate GGML/XCFramework track, not reusing our downloader (B, E).
- `plans/SPEC_model_registry_and_base_dir.md` — original downloader motivation: multi-Parakeet + user base dir; references `Seshat*` names (doc drift flagged by E).
- `plans/central/LAYER_6_model_selection.md` — model selection surface; references `Seshat*` (doc drift).
- `Sources/PersonalScribeCore/Models/Selection/ModelDescriptor.swift:4-6` — "Reserve shape for future engines (parakeetCTC, whisper, etc.)" — reserves enum shape only, not downloader behavior.
- `.build/checkouts/FluidAudio/Sources/FluidAudio/DownloadUtils.swift:127-143, 253, 268-476, 489-509` — corrupt-model retry loop + downloadWithProgress delegate (A).
- `.build/checkouts/FluidAudio/Sources/FluidAudio/ModelRegistry.swift:56-62` — hard-coded `resolve/main/` URL template (A).

---

## Next step

Await user decision on:
- Option 1 go/no-go.
- The four open unknowns above.

On go, draft the three atomic commits (TDD for each): Step 1 wire + delete, Step 2 Settings progress, Step 3 session-start gate. Failing-test-first per each step per project TDD discipline.
