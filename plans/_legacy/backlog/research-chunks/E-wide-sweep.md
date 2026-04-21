# E — Wide-sweep review of the model-download subsystem

Fresh, orthogonal read of everything in the model-prep path that agents A (FluidAudio download API), B (plan provenance), C (git + engine-agnostic framing), and D (phase-trace + test inventory) are NOT covering. File:line throughout.

---

## Non-obvious couplings to the phase enum

The `ModelDownloadProgress.Phase` enum is defined in `/Users/nitinkum/Projects/nitkrar/personal_scribe/Sources/PersonalScribeCore/Protocols.swift:39-44`. Grep shows the enum values are consumed in **only** these logical places, but several have subtle fan-out.

1. **Producers (emit phases).**
   - `Sources/PersonalScribeTranscription/FluidAudioModelDownloader.swift:74-93` — emits `.downloading` mid-loop and on each file completion.
   - `Sources/PersonalScribeTranscription/FluidAudioTranscriber.swift:78,96,118` — emits `.idle` on failure, `.loading` after download returns, `.finished` after `inference.loadModel` returns.
   - `Sources/PersonalScribeTranscription/Models/Selection/ModelAwareFluidAudioTranscriber.swift:97,226,247,319-326` — same pattern (`.idle` on failure, `.loading` after download, `.finished` via `finishedSnapshot`). `download(progress:)` also emits a synthetic `.finished` (line 118-120) with a path that doesn't go through `.loading` at all.
   - `Sources/PersonalScribeTranscription/ModelArtifactStaging.swift:21-35` — `normalizedProgress` only gates `.downloading ∧ .downloading`; anything else pass-through.

2. **Consumers — the pill** (expected).
   - `Sources/PersonalScribeCore/AppStore/AppStore.swift:301-308` — `normalize` collapses `.idle`/`.finished` to `nil`. After this normalizer, downstream code only ever sees `.downloading` or `.loading` (or `nil`). **This is the first load-bearing coupling: the pill never sees `.finished`.** A `.finished` arrival is indistinguishable from "no progress object" — it's silently dropped, not explicitly rendered.
   - `Sources/PersonalScribeCore/AppStore/AppStore.swift:343-364,366-381` — `idleVisibility` / `transcribingVisibility` both branch `.downloading → .downloading(fraction)` and `.loading → .loading`.
   - `Sources/PersonalScribeAppKit/Overlay/PillOverlayViewModel.swift:89-126` — compatibility-only helpers with identical branching (used by `PillOverlayView`-linked legacy apply path + old tests per `plans/central/drafts/stage3/layer_4_inventory.md:40`).

3. **Non-pill consumers (the surprises).**
   - `Sources/PersonalScribeAppKit/MenuBar/MenuBarSceneModel.swift:10,43,168` — `@Published var preparationProgress: ModelDownloadProgress?` is mirrored onto the menu-bar scene model. Nothing in `StatusItemMenuModel`, `StatusItemController`, or the menu-rebuild path reads it, but it is **published** — any future `objectWillChange` subscriber gets it for free, and test `Tests/PersonalScribeAppKitTests/MenuBarSceneModelTests.swift:377-402` asserts `.downloading`/`.loading`/`nil` transitions through the scene model. Mirrors to nowhere today, but not strictly unused — it's part of the scene-model contract.
   - `Sources/PersonalScribeAppKit/Overlay/PillOverlayController.swift:19-44,254` — the controller publishes `preparationProgressPublisher: AnyPublisher<ModelDownloadProgress?, Never>` as a constructor input; callers still pass it through. This suggests the pill overlay could be re-wired back to the raw progress stream (pre-AppStore) if the AppStore route is inadequate — the seam exists.
   - **No menu-bar / status-item / telemetry / first-run gate branches on `.downloading`/`.loading` today.** The phase enum is a pill-centric contract; `MenuBarSceneModel` is the only subscriber outside the pill, and it is read-only. Good news: changing the enum's shape (to, say, a unified `.preparing(fraction:)` with an optional rate-estimate substate) has **low blast radius** beyond pill + AppStore normalize.

4. **Not coupled to phases (worth noting explicitly).**
   - `SessionCoordinator.prepareTranscriber()` at `Sources/PersonalScribeSession/SessionCoordinator.swift:152-158` forwards to pipeline, ignoring progress phases — it only signals throw/no-throw.
   - `Sources/PersonalScribeSession/Pipeline/Orchestrator/SessionPipelineOrchestrator.swift:453-466` (`prepareTranscriberInBackground`) fires prepare in `Task.detached` **inside `startRecording`** (line 186). This means the recording-start path **races the prepare path**: if prepare has never been called and the user hits the hotkey, capture begins, `.recording` ships to the pill (hiding any pending `.downloading`/`.loading`), and prepare happens while recording — then when the user releases the hotkey, `.transcribing` surfaces the still-in-flight `.loading` phase through the pill. That's the observed multi-minute `.loading` spell.

---

## Design notes for/against engine-agnostic downloader

Defer to C for git-history verdict. Lane-level in-source/plan evidence I found:

- **Against engine-agnostic (strongest signal).** `Sources/PersonalScribeTranscription/Models/Selection/ModelArtifactStaging.swift:58-68` hardcodes `parakeet_vocab.json` as a required artifact *and* validates its first byte is `{` or `[`. Identical hardcoding repeats at `Sources/PersonalScribeSession/Models/Selection/ModelBoundTranscriberProvider.swift:90-98` (validator) and `Sources/PersonalScribeTranscription/FluidAudioTranscriber.swift:282` (legacy validator via ModelArtifactStaging). A whisper.cpp engine would ship `ggml-*.bin` + a tokenizer JSON with a different name/shape entirely; the validator would reject it. **The staging/validation is Parakeet-shaped, not engine-agnostic.**

- **Comment-level reservation (neutral).** `Sources/PersonalScribeCore/Models/Selection/ModelDescriptor.swift:4-6`:
  ```swift
  public enum TranscriptionEngine: Sendable, Equatable {
      case parakeetTDT
      // Reserve shape for future engines (parakeetCTC, whisper, etc.).
      // Do not implement them now.
  }
  ```
  The *type* reserves the enum shape, but note the qualifier "Do not implement them now." — reservation is a compile-time hook, not an active downloader-level abstraction.

- **DECISIONS line 51 is the authoritative "no" on engine-agnostic plumbing:**
  `/Users/nitinkum/Projects/nitkrar/personal_scribe/DECISIONS.md:51`:
  > `TranscriptionEngine protocol (swap engines)` — **Rejected** — "Different APIs, model formats; adds complexity for no v0.1 payoff"
  This is the locked, owner-confirmed decision: the project is **not** pursuing an abstract engine protocol. `TranscriptionEngine` in code is a descriptor tag, not a dispatcher.

- **whisper.cpp intent is still in scope, BUT as a separate module.** `PROPOSAL.md:61,154,318,359` all mention whisper.cpp as a "v0.2+ non-English fallback" using **GGML models** and a **separate XCFramework**. `BACKLOG.md:240` lists `whisper.cpp integration for non-English` in "Future (not yet scoped)". Every reference positions whisper.cpp as its own stack — different model format (GGML binary blob, not CoreML `.mlmodelc`), different loader (ggml-quantized tensors, not `AsrModels.load`), different vocab mechanism (BPE tokenizer JSON or SentencePiece, not Parakeet's `parakeet_vocab.json`).

- **Layer 6 plan treats the downloader as Parakeet-bound.** `plans/central/LAYER_6_model_selection.md:61-63` places `FluidAudioRuntimeVariant` in a namespace called `FluidAudioRuntimeVariant` with the explicit comment "This is internal to the transcription bridge; UI and storage still traffic in `ModelDescriptor` and `ActiveModelDescriptor`." Runtime-variant mapping is scoped to FluidAudio; there is no analogous WhisperRuntimeVariant type or a sibling engine-switch point in the plan.

- **`ModelDescriptor.resolveURL` hardcodes the HuggingFace URL template.** `Sources/PersonalScribeCore/Models/Selection/ModelDescriptor.swift:36-40`:
  ```swift
  public func resolveURL(for relativePath: String) -> URL {
      URL(string: "https://huggingface.co/\(repository)/resolve/\(revision)/\(relativePath)")!
  }
  ```
  This *happens* to also work for whisper.cpp's ggerganov HF repos (they serve GGML files at the same URL shape), so the descriptor isn't *fundamentally* parakeet-only — the HTTP-fetch loop is reusable if someone wires a GGML descriptor. But that reuse is coincidental, not designed.

**Verdict (for E's lane):** There is **no documented design-note arguing FOR engine-agnostic downloading**. The descriptor types have enough generality to be re-pointable at a GGML repo, but the staging, validation, and artifact-shape logic is Parakeet-specific and would need parallel paths for whisper.cpp. Deleting `PrivateModelDownloader` today does not block a whisper.cpp future — whisper.cpp will ship its own path either way.

---

## Eager prefetch / warmup — present or absent?

**Present, but weakly.**

- `Sources/PersonalScribeAppKit/Composition/AppStartupCoordinator.swift:34-64` runs a background `Task(priority: .background)` at app launch that (a) waits `hotkeyDelay` (250ms), (b) starts the hotkey monitor on MainActor, (c) waits `prepareDelay` (1000ms), then (d) calls `prepareTranscriber` — which is `AppComposition.sessionCoordinator.prepareTranscriber()` (composition at `Sources/PersonalScribeAppKit/Composition/AppComposition.swift:122-134`).

- Path: `AppStartupCoordinator` → `SessionCoordinator.prepareTranscriber` → `SessionPipelineOrchestrator.prepareTranscriber` → `CoordinatorPipelineTranscriber.prepare` (`SessionCoordinator.swift:354-357`) → `resolvedActiveTranscriber()` (which via `ModelService.activeDescriptor.voiceModel` hits `ModelBoundTranscriberProvider.transcriber(for:)`) → eventually `ModelAwareFluidAudioTranscriber.prepare()`.

- **Gap 1: the fraction is observed but not surfaced.** This eager path runs *without* any UI consumer of the progress stream. `AppStartupCoordinator` takes `prepareTranscriber: @Sendable () async -> Void` — no progress callback, no phase subscriber. The progress stream is published through `SessionCoordinator.modelDownloadProgress()` → `AppStore.handleModelDownloadProgressChange` → pill. The pill is idle-hidden by default (`AppStoreVisibilityMode.autoShow` per BACKLOG line 115), so during the eager prefetch the user sees **nothing** unless they have `.alwaysOn`. On a first launch where the user opens the Unified Window or the menu bar, download progress is still piped to pill→AppStore, but the pill is suppressed in `.autoShow` idle visibility (`AppStore.swift:343-364`: idle + `.autoShow` → `.hidden`). *Wait — re-read:* `idleVisibility` early-returns `.downloading(fraction)` before the mode check (line 347-355). So `.downloading` *does* override `.autoShow` hidden during idle. Good — the pill will appear during eager prefetch. But once it flips to `.loading`, same override applies.

- **Gap 2: prepare starts ~1.25s after launch.** Combined 250ms + 1000ms delay means the first ~1.25s of the app has no model-prep activity. Historical context (BACKLOG line 45): cold-launch `prepareTranscriber` measured 730-750ms on a Phase 1 dogfood build — that's the **`.loading` duration alone** for a warm-disk case. On first-ever launch the load is preceded by a ~450MB silent fetch inside `AsrModels.load` (if A's thesis holds), which is where the multi-minute `.loading` spell comes from.

- **Gap 3: nothing else prefetches.** Menu-bar open, onboarding window open, settings window open — none of these trigger `prepare()`. Onboarding routing (`PersonalScribeAppMain.swift:181-185`) opens the Unified Window to Settings tab for first-run permission requests, but doesn't touch the transcriber. `AIModelsTab.swift` is read-only metadata — no download button, no refresh action. First recording attempt calls `SessionPipelineOrchestrator.prepareTranscriberInBackground` (line 186) which races against capture.

- **Deliberate or gap?** No comment in `AppStartupCoordinator` or `AppComposition` explains *why* there's a 1s `prepareDelay`. `BACKLOG.md:45` documents the Phase 1 rationale: `"Task.detached in 1cb665c; signposts instrument prepare path"` — the detached-to-background pattern was a fix for "app unresponsive at launch" (P0 #1). The 1s delay is presumably to let AppKit finish scene/menu/status-item setup before taking CPU on the model load. But there is **no design note** stating that — if you reduce `prepareDelay` to 0, nothing tells you not to.

- **Design discipline signal:** DECISIONS line 44-45 explicitly says `17 | Model pre-warming can wait until v0.2` — *Hypothesis to validate*. PROPOSAL line 298 in Phase 2 lists "Model pre-warming on launch + wake". The current eager prefetch is a v0.1-incidental because P0 #1 forced `Task.detached`, not because pre-warming shipped. In that sense, the eager path exists but **isn't advertised as an intentional warm-up** — it's the by-product of a different fix.

---

## Cold / warm-partial / warm-full launch narrative

Walking the code for the three scenarios, citing branches.

### Cold launch (first ever run, empty `~/Library/Application Support/personal_scribe/models/`)

1. `PersonalScribeAppMain.init` builds composition, starts `appStore`, starts `sceneModel.startObserving()`, starts `startupCoordinator` (`PersonalScribeAppMain.swift:55-175`).
2. `AppStore.start()` spins up `modelDownloadProgressObservationTask` which subscribes to `SessionCoordinator.modelDownloadProgress()` (`AppStore.swift:89-94`). Initial snapshot from `SessionDownloadProgressBroadcaster` is `.idle` (`SessionCoordinator.swift:545-550`), `normalize` maps to `nil`, no UI effect.
3. `AppStartupCoordinator.start()` sleeps 250ms, starts hotkey monitor, sleeps 1000ms.
4. At t≈1.25s, `coordinator.prepareTranscriber()` runs. Through the chain, this lands in `ModelAwareFluidAudioTranscriber.performPrepare`.
5. `modelDirectory` resolves to `<base>/models/parakeet-tdt-0.6b-v2/` (`ModelAwareFluidAudioTranscriber.swift:250-258`). Directory is created if missing but empty.
6. `Self.modelArtifactsAreValid(in:descriptor:)` returns false (`ModelAwareFluidAudioTranscriber.swift:328-359`). Branch into `ensureValidDownloadedModel`.
7. `PrivateModelDownloader.ensureModelAvailable` loops `descriptor.requiredRelativePaths` (5 items for v2). For each file, it byte-streams from HuggingFace (`FluidAudioModelDownloader.swift:44-94`), emitting `.downloading` with fraction `(i + fileFrac) / 5` at ≥500ms cadence.
8. **Pill transitions:** `.hidden` → `.downloading(0.0+)` → pill slides up from idle/hidden (`AppStore.derivePillVisibility` + `idleVisibility` emit `.downloading` for idle state). Percent climbs 0 → ~20% → 40% → 60% → 80% → 100% as each file completes. **Duration: a few seconds** (the 5 files are `coremldata.bin` metadata files + `parakeet_vocab.json`, all small — D confirms bytes are trivial).
9. After download loop, `progressBroadcaster.update(.loading, fractionCompleted: 1, ...)` (`ModelAwareFluidAudioTranscriber.swift:225-227`).
10. **Pill transitions:** `.downloading(1.0)` → `.loading` — spinner + "Loading model…" text. User sees this pill from the percent ending to...
11. `inference.loadModel(from: modelDirectory, runtimeVariant:)` runs (`ModelAwareFluidAudioTranscriber.swift:233-236`). This calls `AsrModels.load(from: directory, version: runtimeVariant.asrModelVersion)` (`ModelAwareFluidAudioInferenceClient.swift:28-33`). **Here be A's dragons** — per FluidAudio docs (`.build/checkouts/FluidAudio/Documentation/ASR/ManualModelLoading.md:54`), `AsrModels.load(from:)` is documented to be no-network, but only if the staged bundles are complete. Our `requiredRelativePaths` only list `coremldata.bin` files, NOT `model.mil`, NOT `weights/weight.bin`, NOT `metadata.json`. `AsrModels.load` presumably falls back to its own HF fetch to fill the missing bundle parts. Defer to A for confirmation.
12. During step 11, pill stays on `.loading` for however long the silent fetch + CoreML compilation takes. BACKLOG line 45 measured 730-750ms first-run — but that was Phase 1 (`ee09c569…` Parakeet-TDT v2), and presumably on a machine with `~/Library/Application Support/FluidAudio/Models/` already warm from prior VoiceInk/evaluation use. On a truly cold machine with no prior FluidAudio usage anywhere, the multi-minute `.loading` reported in the bug brief is consistent with FluidAudio doing a silent ~450MB re-download over its own cache path.
13. `inference.loadModel` returns → `progressBroadcaster.update(.finished, ...)` (`ModelAwareFluidAudioTranscriber.swift:247`). `normalize` maps to `nil`. Pill transitions `.loading` → `.hidden` (idle + no progress + `.autoShow` → `.hidden`).

### Warm-partial launch (models/ exists but corrupt, or only some bundles)

1. Steps 1-5 identical.
2. `modelArtifactsAreValid` returns false because at least one `coremldata.bin` is missing or zero-size, OR `parakeet_vocab.json` is missing/doesn't start with `{`/`[`.
3. `ensureValidDownloadedModel` runs. The first attempt wipes `stagingDirectory` (`FluidAudioModelDownloader.swift:31` + fallthrough on failure at line 100-102). Then re-downloads the 5 files fresh from HF. **NOTE:** The downloader does NOT wipe `modelDirectory` until the staging move at line 96-97. Existing partial content in `modelDirectory` (e.g. from a prior aborted download or FluidAudio's own cache) **persists** until the move step.
4. Post-download, same `.downloading` → `.loading` → `.finished` dance as cold.
5. **Gap not covered elsewhere:** if the model directory has SOME bundles but not all (e.g. user `rm`'d one `.mlmodelc`), the validator returns false and re-downloads the 5 in requiredRelativePaths — but the *other* `.mlmodelc`s (Encoder, Decoder, JointDecision) in the same directory remain untouched by our loop. When `AsrModels.load` runs, it sees a mixed-state directory. Behaviour here depends on FluidAudio's internal handling (defer to A).

### Warm-full launch (models/ is complete + last load successful)

1. Steps 1-5 identical.
2. `modelArtifactsAreValid` returns true — the 5 listed files exist, vocab starts with `{`, coremldata.bin sizes > 0.
3. **`ensureValidDownloadedModel` is skipped entirely** (`ModelAwareFluidAudioTranscriber.swift:221-223` branch). No `.downloading` emission.
4. Immediately emit `.loading` (line 225-227).
5. `inference.loadModel` runs. If the on-disk bundles are complete (all sub-files of each `.mlmodelc` present — which is the case if the user's prior session successfully downloaded via FluidAudio's own auto-fill mechanism), this is a pure CoreML compile+load and takes ~500-750ms per BACKLOG line 45.
6. `.finished` → pill hides.

**The warm-full branch is the "happy path"; the cold branch is where the bug lives.** The warm-partial branch is the one that would silently re-download into FluidAudio's private cache without us ever emitting `.downloading` — because our validator passes on just the 5 index files.

---

## Doc–code drift

1. **SPEC_model_registry_and_base_dir.md uses `Seshat*` names throughout.** `plans/SPEC_model_registry_and_base_dir.md:33,92,156,193,225,227,233` reference `SeshatCore/ModelRegistry.swift`, `SeshatConfig`, `SeshatTranscription/FluidAudioTranscriber.swift`. Post-rename these live at `PersonalScribeCore/Models/Selection/BuiltInModelCatalog.swift`, `AppConfig`, `PersonalScribeTranscription/…`. The spec is historical; no plan to update. Agents searching for "ModelRegistry" (enum name) will get zero hits in source — the new name is `BuiltInModelCatalog`.

2. **LAYER_6 plan also still uses `Seshat*` names.** `plans/central/LAYER_6_model_selection.md` — every file path is pre-rename. Fine historically, but an agent landing on the plan without reading the rename memory will grep for symbols that don't exist.

3. **PROPOSAL.md:171 "~/Library/Application Support/personal_scribe/" ≠ actual bundle ID path.** The actual `AppConfig.liveStorageLocator()` produces `<applicationSupportDirectory>/Seshat/` from the pre-rename default (grep for `"Seshat"` in `Config.swift`/storage layer — the folder name `Seshat` may still be baked in). If drift here, a fresh-install user's models land in `~/Library/Application Support/Seshat/` not `.../personal_scribe/`. **FLAG — worth a separate verification.** (Out of scope to fix in this research pass.)

4. **`PillOverlayViewModel.apply(sessionState:preparationProgress:)` is dead-ish.** `plans/central/drafts/stage3/layer_4_inventory.md:40` flags it as a live compatibility method. Grep confirms it's still called from `PillOverlayView.swift` (not directly — only via pill view) and 30+ test-file call sites. This is a Stage-2 shim that should be deleted post-tests-rewrite (BACKLOG line 191 records the equivalent debt for `FluidAudioTranscriber`). Same pattern.

5. **AIModelsTab.swift advertises a phase that doesn't exist in plan.** `Sources/PersonalScribeAppKit/Settings/AIModelsTab.swift:27`: `Text("Model switching lands in Phase 3.F.")`. There is no "Phase 3.F" in `PROPOSAL.md` (phases 1-4 only) — it's a LAYER_6-plan internal designation (`plans/central/LAYER_6_model_selection.md:245` mentions `"the parked 3.F second-model work"`). The user-facing label leaks an internal-plan phase number that won't map to anything in BACKLOG/PROPOSAL.

6. **BACKLOG line 196-197 explicitly calls out** that `AIModelsTab` is **not a Stage 2 gap** — "Phase 3.F future feature per its own source comment". Any future refactor proposal for AIModelsTab should cite BACKLOG first.

7. **Decisions line 17 (pre-warming deferred to v0.2) vs. current eager-prefetch behaviour.** The current `AppStartupCoordinator.prepareTranscriber` *is* pre-warming. DECISIONS still lists it as a "Hypothesis to validate / Deferred to v0.2". This is not a breaking contradiction (we shipped it anyway), but DECISIONS should be updated when the behaviour stabilizes.

---

## Settings UI model-state surface

`Sources/PersonalScribeAppKit/Settings/AIModelsTab.swift` (full file, 49 lines).

- It renders **only static metadata** from a statically-injected `ModelDescriptor` (default: `BuiltInModelCatalog.parakeetTDT06Bv2`).
- It displays `displayName`, `id`, `repository`, `revision`, and a static `StatusPill(status: .ready, label: "Current")` — **`.ready` is hardcoded regardless of actual disk state**.
- There is **no** consumer of `ModelService.isDownloaded(_:)`, no `modelDownloadProgress()` subscription, no download button, no progress indicator, no refresh action.
- Consequence: even on a cold launch where the model has never been downloaded, AIModelsTab shows `.ready` / `Current`. This is **misleading but harmless** — the user can't download/switch anything, so the mis-displayed status has no gating effect.

**`AIModelsTab` does NOT have the `.downloading` → `.loading` UX bug because it never displays the phase at all.** It cannot regress either — zero progress wiring.

**Modes-tab path.** `Sources/PersonalScribeAppKit/UnifiedWindow/Tabs/ModesTab.swift` + `ModesTabViewModel.swift` + `PersonalScribeAppMain.swift:134-143`: when the user taps a mode that implies a different voice model, `modelService.setActive(modelService.descriptor(for: mode))` runs. `DefaultModelService.setActive` (line 78-87) calls `download(canonical.voiceModel) { _ in }` — **progress handler is a no-op closure**. If the target model isn't downloaded, this kicks off a silent ~450MB download **from inside a Settings click**, with no UI feedback. The download progress *does* still flow through `ModelBoundTranscriberProvider.download → ModelAwareFluidAudioTranscriber.download → progressBroadcaster`, but that broadcaster feeds the transcriber's own stream, which `SessionCoordinator` only subscribes to when `beginRecordingSession()` starts observing the current recording-session transcriber (`SessionCoordinator.swift:442-455`). **If the user is not recording, the active-model download progress from a Settings click likely never reaches `AppStore`/pill.**
  - This is the **second variant** of the same UX bug: cold-start + Modes-tab switch = silent multi-minute download with zero user feedback.
  - Suggest a scope-check with agents B/D on whether any test covers this flow.

---

## Anything else surprising

1. **Progress is only subscribed via one path.** `CoordinatorPipelineTranscriber.observeDownloadProgress` (`SessionCoordinator.swift:442-455`) cancels and re-subscribes per-recording-session, tied to which transcriber is active for that session. If the user switches models via Modes tab between recordings, the observer is torn down and re-established. The `progressObservationTask` is owned by the pipeline-transcriber actor, not by `SessionCoordinator` directly. Net: **there's no persistent progress observer**. Each recording session re-opens the stream. This is fine for the pill, but means any long-running background prefetch (e.g. eager startup prepare) only publishes progress if its transcriber is the currently-observed one. Since `AppStartupCoordinator` calls `prepareTranscriber` which resolves the active-voice-model transcriber, it *should* be the same instance as the first recording session's — but this is implicit from the cache in `ModelBoundTranscriberProvider.transcribers` (`ModelBoundTranscriberProvider.swift:9,52-60`), not enforced.

2. **Two separate transcriber paths coexist.** `FluidAudioTranscriber` (legacy fixed-descriptor) and `ModelAwareFluidAudioTranscriber` (model-selection-aware) both exist and both have near-identical download+broadcast logic (`FluidAudioTranscriber.swift:234-273` vs `ModelAwareFluidAudioTranscriber.swift:260-296`). BACKLOG line 191 confirms this debt. **For the UX-bug fix,** changes must be applied in both, unless the fix lands post-legacy-transcriber deletion. Flag for the coordinator agent.

3. **`download(progress:)` on `ModelAwareFluidAudioTranscriber` exists but is only called from `ModelBoundTranscriberProvider.download` (line 46)** — which is itself only called from `DefaultModelService.download` (line 109) — which is only called from `DefaultModelService.setActive` (line 82) with a no-op handler. So the "explicit download with progress callback" path exists in the API but has **zero live consumer** today. That's a seam a fix could exploit: a Settings UI "Download now" button could call it with a real handler.

4. **No disk-space precheck.** `ModelDescriptor.approximateSizeBytes` (e.g. 450_000_000 bytes for v2, 700_000_000 for v3 — `BuiltInModelCatalog.swift:26,52`) is defined but **never read**. `SPEC_model_registry_and_base_dir.md:50` anticipated "for display and disk-space checks" — neither has shipped. A user on a full disk would see the download fail mid-transfer; no precheck.

5. **`Task.detached(priority: .background)` in `prepareTranscriberInBackground`** (`SessionPipelineOrchestrator.swift:457`). Using `.background` QoS for a 1GB network pull is reasonable battery-wise, but `URLSession.bytes(for:)` honors QoS and could throttle the download further during first-run. Potentially exacerbates the perceived "multi-minute loading". Worth a timing measurement.

6. **`FluidAudioModelDownloader` uses `.bytes(for:)` + per-byte append.** Line 59-61 builds the data buffer byte-by-byte (`data.append(contentsOf: [byte])`). This is **O(n²)** for a naive Swift Array/Data with CoW behaviour at boundary reallocations. For 5 tiny files (<1MB each), this is fine; for a hypothetical migration to downloading the big `.mil`/`weights.bin` files (tens to hundreds of MB each), this would be pathologically slow vs. `URLSession.download(for:)` or buffered-chunk writes. **If the fix is "make the custom downloader the source of truth for all weights", this loop needs rewriting first.**

7. **Test coverage exists for the state-machine transitions but likely not for the `.loading` duration.** Defer to D for the inventory, but note: `Tests/PersonalScribeAppKitTests/MenuBarSceneModelTests.swift:377-402` exercises `.downloading`/`.loading`/`nil` at the scene-model level. Nothing I found tests the wall-clock duration spent in `.loading`, and nothing asserts "`.loading` emits AND finishes within N seconds" — which is exactly the bug's signature.

---

## Citations index (file:line references for reviewer cross-check)

- Phase enum definition: `Sources/PersonalScribeCore/Protocols.swift:38-62`
- Phase normalizer in AppStore: `Sources/PersonalScribeCore/AppStore/AppStore.swift:301-308`
- Derive pill visibility: `Sources/PersonalScribeCore/AppStore/AppStore.swift:310-381`
- Eager prefetch: `Sources/PersonalScribeAppKit/Composition/AppStartupCoordinator.swift:34-64`
- Prefetch composition: `Sources/PersonalScribeAppKit/Composition/AppComposition.swift:116-137`
- Prepare racing capture: `Sources/PersonalScribeSession/Pipeline/Orchestrator/SessionPipelineOrchestrator.swift:186,453-466`
- Model-aware validator: `Sources/PersonalScribeTranscription/Models/Selection/ModelAwareFluidAudioTranscriber.swift:328-359`
- Descriptor URL template: `Sources/PersonalScribeCore/Models/Selection/ModelDescriptor.swift:36-40`
- Descriptor requiredRelativePaths: `Sources/PersonalScribeCore/Models/Selection/BuiltInModelCatalog.swift:4-17`
- Settings-triggered silent download: `Sources/PersonalScribeSession/Models/Selection/DefaultModelService.swift:78-87`
- AIModelsTab read-only: `Sources/PersonalScribeAppKit/Settings/AIModelsTab.swift:16-48`
- Engine-agnostic rejection: `DECISIONS.md:51`
- Engine-tag reservation: `Sources/PersonalScribeCore/Models/Selection/ModelDescriptor.swift:4-6`
- whisper.cpp future-parking: `BACKLOG.md:240`, `PROPOSAL.md:61,154,318,359`
