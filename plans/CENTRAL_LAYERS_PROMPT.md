# Central Layers — Plan-Writing Prompt

## What this file is

A standalone prompt to hand to a codex subagent (`codex-cc:codex-rescue`) to produce **9 implementation plan files** for the central-layer refactor of Seshat. The codex agent writes markdown plans, not code. Implementers (future codex + main-session) execute the plans verbatim.

## How to use

Hand this entire file to codex via `Agent` tool with `subagent_type: codex-cc:codex-rescue`. Codex produces the deliverables described under "Deliverables" below.

## Critical discipline (baked into every plan file + every step)

Every plan file MUST open with this paragraph, verbatim:

> **Do NOT diverge from this plan. Silent divergence is the cardinal sin. To deviate, surface the proposed divergence in a commit-message comment AND in the hand-off report; wait for main-session confirmation. Paraphrasing the contract is divergence. Renaming a protocol the plan specifies is divergence. Choosing a different storage format than the plan specifies is divergence.**

Every step's validation checklist MUST reference specific `file:line` in produced code + specific plan clauses. Implementers tick box-by-box in their hand-off report.

## Working directory

`/Users/nitinkum/Projects/nitkrar/seshat`. Branch `trunk`. `plans/reviews/`, `plans/backlog/`, `plans/seshat manus resources/`, `plans/App UI design/` are all out-of-scope for the plan writer — read-only references only.

## Inputs to read before writing any plan

Committed source:
- `Sources/SeshatCore/**/*.swift`
- `Sources/SeshatAppKit/**/*.swift`
- `Sources/SeshatSession/**/*.swift`
- `Sources/SeshatAudio/**/*.swift`
- `Sources/SeshatTranscription/**/*.swift`
- `Tests/**/*.swift` — to understand test seam patterns

Reference docs / prior plans:
- `plans/App UI design/Seshat UI Polish & Unified Window Implementation.md` — UI bundle spec
- `plans/App UI design/Seshat Q4_Q5 Handoff Spec.md` — Manus resolutions
- `plans/App UI design/SeshatTheme.swift` — drop-in theme file (replaces current)
- `plans/PHASE_0_rename.md`, `plans/PHASE_1_permission_service.md`, `plans/PHASE_2_unified_ui.md`, `plans/SEQUENCING_MASTER.md` — earlier phase plans (may still be in-flight; if absent, produce this central-layers structure from scratch)
- `BACKLOG.md` — especially the parked items (personal dictionary, streaming dictation, speaker verification, 7-stage post-processing) which pre-scope some of these layers

## Execution strategy: parallel-build then swap (IMPORTANT)

Every layer's plan MUST be structured as **three stages**, not one:

- **Stage 1 — Build in parallel.** Produce the new layer's types / protocols / live implementation / tests in NEW files, in NEW directories (e.g. `Sources/SeshatCore/Permissions/*`, `Sources/SeshatAppKit/Output/*`, etc.). **Do not touch any existing consumer.** Existing types and call sites remain untouched during Stage 1. New layer must build-green + test-green against its own fakes/tests, without the rest of the app integrating it yet. A Stage-1 commit can land in isolation.
- **Stage 2 — Swap.** Migrate each existing consumer to use the new layer. The old types still exist but are no longer referenced. One consumer per sub-step; consumers listed exhaustively in the plan; each gets its own commit for easy revert.
- **Stage 3 — Delete.** Remove the old types, protocols, files. Only runs after every consumer is on the new layer AND build is green.

Rationale: decouples new-layer correctness from migration-risk. New layer lands + gets reviewed in isolation; swap is mechanical; delete is the last step. Also enables running stage-1 builds for non-overlapping layers in parallel (different subagents, different directories, no collisions).

Each layer's plan MUST:
- Label every step as Stage 1 / Stage 2 / Stage 3.
- State which OTHER layer Stage 1s it can parallelize with (e.g., Layer 3 Stage 1 can run parallel to Layer 9 Stage 1 since they touch different directories).
- State which layer's Stage 2 it depends on (e.g., Layer 4 Stage 2 requires Layer 1 Stage 2 complete because AppStore reads permission statuses from the real service).
- Defer Stage 3 deletions to INDEX.md's global "Stage 3 — Deletion pass" section at the end.

Collision rules for parallel Stage 1 work:
- New types MUST live in new directories. Don't extend existing files.
- If two layers need to add new files to the same directory (e.g., both add to `Sources/SeshatCore/`), they must claim disjoint subdirectories (e.g., `Sources/SeshatCore/Permissions/` vs `Sources/SeshatCore/Storage/`).
- No Stage 1 touches `Package.swift` product or target definitions unless it genuinely needs a new SPM target (none of these 9 layers do). If it thinks it does, flag as `[QUESTION]`.

## Locked design decisions (from user — use as-is, do not reopen)

1. **Merged rename + permission refactor.** Don't produce a separate rename phase. The permission-layer types get their final un-prefixed names at creation time. Broader `Seshat` prefix rename on non-permission types (e.g., `SeshatPasteMode` → `PasteMode`) rides along as part of the relevant centralization layer (e.g., `PasteMode` rename happens inside Settings layer work since it's one of the 7 typed resolvers being unified). Exceptions that keep a non-`Seshat` but non-colliding prefix: `SeshatError` → `AppError`, `SeshatLogger` → `AppLogger`.
2. **SPM target names unchanged.** `SeshatAppKit`, `SeshatCore`, `SeshatAudio`, `SeshatSession`, `SeshatTranscription`, `SeshatTestSupport` stay as-is this phase. Target rename is a separate deferred phase.
3. **UserDefaults key rename is safe without migration.** Sole user, no persistence-back-compat concern.
4. **No MVP vs full-ship split.** Everything per layer lands in one phase, EXCEPT specific stubs explicitly authorised in Phase 2 UI work (Home-tab complex metrics, Mic device picker, Launch-at-login, Show-in-Dock, Check-for-Updates — those ship as visible stubs plus backlog tickets).
5. **`AVAudioCaptureService.swift:41`** direct `AVCaptureDevice.authorizationStatus` guard stays as defense-in-depth. Do NOT inject the permission service into `SeshatAudio`.
6. **AX is optional everywhere.** `OnboardingViewModel:18` already treats AX as optional; `OnboardingWindowController:98` (or successor) must match. Paste falls back to clipboard when AX not granted — that's the design intent.
7. **No `type` / `kind` / `intent` column in the SQLite transcript schema.** Phase-3 design lock per `project_phase3_notes_equals_history.md`. Any metrics computation must NOT invent a schema type column.
8. **Streaming output delivery mechanism (CGEvent synthetic keypresses vs incremental Cmd+V) is DEFERRED.** The Output layer plan identifies the two approaches, lists trade-offs, and leaves the decision for user review during implementation. File the decision as a backlog item: `plans/backlog/streaming-output-delivery-mechanism.md`.
9. **Website / Privacy / Terms link rows hide if URL is `nil`.** `AppBrand.websiteURL: URL?` is optional — `nil` means "don't render the row", not "render a disabled placeholder".

## Deliverables

Produce **10 files in one commit** under `plans/central/`:

1. `plans/central/INDEX.md` — master overview with per-layer summary, dependency graph between layers, recommended execution order, table of every numbered step across all 9 layers.
2. `plans/central/LAYER_1_permissions.md`
3. `plans/central/LAYER_2_storage.md`
4. `plans/central/LAYER_3_settings.md`
5. `plans/central/LAYER_4_state_store.md`
6. `plans/central/LAYER_5_output.md`
7. `plans/central/LAYER_6_model_selection.md`
8. `plans/central/LAYER_7_pipeline.md`
9. `plans/central/LAYER_8_metrics.md`
10. `plans/central/LAYER_9_app_brand.md`

Commit subject: `trunk: plans/central — 9-layer centralization plan + master index`. Do NOT run `swift build` / `swift test`. Do NOT write any code.

## Per-layer plan-file structure (mandatory for each)

```markdown
# Layer N — <title>

## Critical discipline
[do-not-diverge paragraph verbatim]

## Why this layer exists
[1-2 paragraphs: what pain it solves, why now, what it enables]

## Observed current spread
| File | Line(s) | What lives there |
|---|---|---|
| ... |

## Proposed API / contracts
### Types (enums, structs)
[names + shapes + field descriptions — NOT code]

### Protocols
[names + method signatures]

### Errors
[if the layer owns its own errors]

## Proposed live implementation
[Shape of the concrete impl: actor vs @MainActor class vs struct, isolation model, dependencies, threading story. Do NOT write code. Describe.]

## Migration of existing call sites
### Step N.M — <site>
| Change | Before | After |

## Test strategy
- Unit tests: what + where
- Integration tests: what + where
- Fakes for the new protocols
- Regression guards the layer must preserve (cite existing tests)

## Open design questions (surface — do not resolve)
- [QUESTION] description, what main-session needs to decide

## Validation checklist (implementer ticks box-by-box)
- [ ] ...
- [ ] No files outside "Observed current spread" modified (unless in explicit collision list)
- [ ] No `Color(hex:` outside `Theme/*` (house rule)
- [ ] No direct `UserDefaults.standard.*` — typed resolvers only
- [ ] No `type` / `kind` / `intent` column added to SQLite
- [ ] `swift build --build-tests` green (main session)
- [ ] All acceptance tests named in plan pass

## Backlog tickets authored
- `plans/backlog/<ticket>.md` — ...

## Inter-layer dependencies
- **Requires**: layer N (why)
- **Blocks**: layer M (why)

## Commit style
`trunk: layer N.M: <verb-led subject>`. Test + fix in same commit.
```

---

## Per-layer scope (read carefully — codex writes plans matching each)

### Layer 1 — Permissions

**Why**: 3 enums, 2 protocols, 5+ scattered sites all re-implementing permission status/request. Inconsistent (mic has async request, IM has request-then-relaunch, AX has route-to-Settings). User has already reviewed a prior permission-service design in `plans/PHASE_1_permission_service.md` if that file exists — USE IT as the skeleton and extend, don't rewrite from scratch.

**Scope IN**:
- Types: `Permission` enum (cases: microphone, inputMonitoring, accessibility), `PermissionStatus` enum (pending, granted, denied), `RequestOutcome` struct (prompted, openedSettings, requiresRelaunch, finalStatus).
- Protocol: `PermissionService: Sendable` — `@MainActor` conforming class.
  - `status(for: Permission) -> PermissionStatus` — sync, non-triggering, reads OS API directly each call.
  - `request(_: Permission) async -> RequestOutcome` — per-permission honest semantics.
  - `statusSnapshot() -> [Permission: PermissionStatus]` — one-shot for whole-app reads.
  - `refresh()` — re-reads all OS states; called on `NSApplication.didBecomeActiveNotification`.
  - `systemSettingsDeepLink(for: Permission) -> URL`.
- Publisher/observable: the service is observable so subscribers (pill, menu bar, Permissions tab) react to `refresh()` automatically. No per-permission AsyncStream — one `@Published` dictionary is enough.
- Live impl: `AppKitPermissionService` in `SeshatAppKit/Permissions/`.
- **AX maps to `.pending` when `AXIsProcessTrusted()` is false**, never `.denied`. The OS API cannot distinguish; don't lie in the enum.
- Delete: `MicrophonePermissionState`, `InputMonitoringPermissionState`, `OnboardingPermissionOutcome`, `PermissionProbing`, `OnboardingPermissionProbing`, `AppKitMicrophonePermissionRequester`, `SeshatOnboardingCompleted` + `OnboardingState.swift`, `PermissionStatus.swift`.
- Migrate call sites: `PasteInjector`, `GlobalHotkeyMonitor`, `MenuBarSceneModel`, `OnboardingViewModel` (or its successor in the Permissions sub-tab), `StatusItemController`, `SeshatAppMain`.
- Rename happens at creation time — no `Seshat` prefix on any new type.

**Scope OUT**:
- Do NOT inject into `SeshatAudio` — locked decision #5.
- `.skipped` (onboarding-era 4th case) moves to UI-level view-model state, NOT the core enum.

**Inter-layer dependencies**:
- Blocks: Layer 4 (state store reads permission statuses), Layer 9 (app brand's TCC deep-link URLs use `systemSettingsDeepLink`).

### Layer 2 — Storage / paths

**Why**: path construction + disk access is spread. `SeshatConfig.baseDirectory()` returns the app root; `TranscriptStore` + `SQLiteTranscriptStore` each compute their own sub-paths; `FluidAudioModelDownloader` has its own cache dir; log files are elsewhere. No single place owns atomic-write helpers or managed subdirectory invariants.

**Scope IN**:
- Types: `ManagedDirectory` enum (cases: models, modes, recordings, logs, cache) — enumerates the fixed subdirectories Seshat owns under the base dir.
- Protocol: `StorageLocator: Sendable` — `@MainActor` or value type.
  - `url(for: ManagedDirectory) -> URL`
  - `baseDirectory: URL`
  - `ensureDirectoriesExist() throws` — idempotent bootstrap on app launch.
- Protocol: `AtomicFileWriter: Sendable` — common save/rename pattern (e.g. used by SQLite migrator tmp-file → rename).
- Value type: `DiskSpaceSnapshot` — used by metrics layer to show "X GB used" in About tab (if Manus adds that).
- Migrate call sites: `SeshatConfig` (likely stays but delegates to the new locator internally), `TranscriptStoreJSONL`, `SQLiteTranscriptStore`, `BaseDirectoryMigrator`, `FluidAudioModelDownloader`.
- Rename: drop `Seshat` prefix where applicable — `SeshatConfig` → `AppConfig` or integrated into `StorageLocator`.

**Scope OUT**:
- Do NOT touch `FluidAudio`'s own checkout cache dir (that's the SPM dep's concern).
- Do NOT re-implement `FileManager` — build on top.

**Inter-layer dependencies**:
- Blocks: Layer 3 (settings need a path for UserDefaults suite if we ever move off `.standard`), Layer 6 (model selection owns the `models/` subdirectory via this layer), Layer 7 (pipeline config lives in `modes/`), Layer 8 (metrics reads from `recordings/`).

### Layer 3 — Settings (Preference<Value>)

**Why**: 7 near-identical ~30-line typed resolvers today (`PasteMode`, `WaveformDecayMode`, `PasteRestoreDelay`, `PillVisibilityMode`, `HotkeyPreference`, `WindowTint`, `PillAppearance`) each hand-roll `default / userDefaultsKey / resolve(from:) / persist(to:)`. Pure boilerplate collapse.

**Scope IN**:
- Type: `Preference<Value: Codable & Sendable>` — generic wrapper.
  - Init takes: `key: String`, `default: Value`, `defaults: UserDefaults = .standard`.
  - API: `resolve() -> Value` (or `get`), `persist(_ value: Value)` (or `set`), `binding() -> Binding<Value>` for SwiftUI.
- Migrate 7 existing resolvers to use `Preference<Value>`. Each becomes ~5 lines of declaration.
- **UserDefaults key rename**: drop `Seshat` prefix from all 7 keys + any others (`SeshatBaseDirectoryPath`, `SeshatActiveModelDescriptor`, etc.). Locked decision #3 — no migration needed.
- Consumers (`GeneralTab`, `ShortcutsTab`, etc.) keep their existing typed view bindings; only the underlying resolver changes.

**Scope OUT**:
- Do NOT touch `Config.swift`'s `testingBaseDirectoryOverride` pattern — that's a separate test-isolation concern.
- Do NOT move `BuildInfo.generated.swift`-style compile-time constants into `Preference`.

**Open questions to flag**:
- [QUESTION] For enum-backed preferences (`PasteMode`, `WindowTint`, etc.), does `Preference<PasteMode>` satisfy `Value: Codable` via raw-value auto-synthesis, or do we need custom `Codable` conformance?
- [QUESTION] For `HotkeyPreference` which is a struct (not enum), same `Codable`-synthesis question — likely fine but verify.

### Layer 4 — State / AppStore (app-wide observable store)

**Why**: state is distributed across `SessionCoordinator`, permission services, active mode, model download progress, pill visibility, recording context. Recent bugs (pill vanishing on transcription error, menu state caching, hotkey stop-from-pill-click) are symptoms of state drift across these. A single source-of-truth prevents views from reading stale partial state.

**SCOPE IS UNDER RESEARCH — codex must investigate first.** Two candidate designs; the plan must compare them with evidence from the current codebase and propose a recommendation, NOT take main-session's framing as locked.

Candidates to research:
- **Candidate A — Facade / republisher.** `AppStore` is a `@MainActor ObservableObject` that subscribes to existing subsystem streams (`SessionCoordinator.stateStream()`, `PermissionService.$permissions`, etc.) and republishes via `@Published` fields. One-directional: subsystem → store → views. Views read store only. No action dispatch, no reducer. Subsystems still own their logic. Minimal disruption.
- **Candidate B — Unidirectional action/reducer store (Redux/TCA-lite).** `AppStore` owns the app's single state tree. Every mutation is a typed action dispatched through the store; subsystems publish events that become actions; reducers produce the next state. Views read via SwiftUI bindings. Consumers change from "call SessionCoordinator.toggle()" to "store.dispatch(.toggleRecording)". Large refactor, bigger payoff for state-consistency, higher learning curve.

Codex MUST produce a comparison in `plans/central/LAYER_4_state_store.md` with these sections:

1. **Observed state-drift bugs in the current codebase.** Cite `file:line` for at least 3 concrete bugs or hazards that either design would fix (e.g., the pill-vanishing-on-error bug pre-fix, the hotkey-from-pill-click bug, the permission-status-staleness on re-install).
2. **Candidate A detailed design.** Types, isolation, wiring, migration per consumer.
3. **Candidate B detailed design.** Action types, reducer shape, side-effect handling (async work), testing strategy, SwiftUI binding pattern.
4. **Side-by-side comparison table** with rows: lines-of-new-code, subsystems-touched, migration-count, test-strategy, debuggability, type-safety, Swift-concurrency ergonomics, learning-curve, risk-of-regression.
5. **Codex's recommendation** with one-sentence rationale. Must pick one, not punt.
6. **Main-session decision gate**: a `[DECISION REQUIRED]` marker at the top of the file calling out that implementation does NOT start until the user signs off on the picked candidate.

Whichever candidate wins, these fields must be reachable from the store (fields or derived):
- `sessionState: SessionState`
- `permissions: [Permission: PermissionStatus]`
- `activeMode: ModeDescriptor?`
- `modelDownloadProgress: ModelDownloadProgress?`
- `pillVisibility` (current derived state, not the user preference)
- `lastTranscriptionResult: TranscriptionResult?`
- `currentRecordingDuration: Duration?` (during `.recording`)

**Scope OUT (both candidates)**:
- Do NOT own session logic — `SessionCoordinator` still drives state transitions.
- Do NOT own permission-request logic — `PermissionService` still drives requests.
- Do NOT introduce third-party TCA dep. If Candidate B is picked, implement a minimal in-house version (~100 LoC).

**Open questions to flag** (in addition to candidate-research):
- [QUESTION] Does the store own derived UI state like `pillVisibility` (current visibility, derived from `sessionState` + user `PillVisibilityMode` preference), or does that stay in `PillOverlayViewModel`? Both candidates must answer this.

**Inter-layer dependencies**:
- Requires: Layer 1 (permissions), Layer 6 (active mode).

### Layer 5 — Output (batch + streaming)

**Why**: today `PasteInjector` handles batch-only post-transcription delivery. Streaming dictation is coming — FluidAudio's `StreamingAsrManager` + EOU partials model — and will emit partial text continuously. Two output flows share routing, target detection, clipboard save/restore, but differ in granularity + rate + undo semantics. A unified service makes both first-class without duplicating logic.

**Scope IN**:
- Types: `OutputMode` enum (`.batch`, `.streaming`), `OutputTarget` enum (`.frontmostApp`, `.clipboardOnly`, `.selfFrontmost — route to clipboard`), `OutputDelivery` enum (`.paste`, `.typeEvents`, `.clipboardOnly`).
- Protocol: `OutputService: Sendable` — `@MainActor` class.
  - `deliverBatch(text: String) async -> OutputResult` — current `PasteInjector.paste(_:)` shape.
  - `beginStream() -> any OutputStreamHandle` — returns a handle.
  - `OutputStreamHandle.append(_ chunk: String)` + `.finalize()` — incremental delivery.
- Implementations:
  - `ClipboardBatchOutput` — writes pasteboard, posts Cmd+V, restores after delay. Current behaviour.
  - `StreamedTypingOutput` — TBD per delivery-mechanism decision (deferred per locked decision #8).
- Migrate `PasteInjector` → `BatchOutput` implementation behind the service. Consumers (`MenuBarSceneModel`, `SessionCoordinator`) inject `OutputService` instead of `PasteInjecting`.
- Respect `PasteMode` (.pasteAtCursor / .clipboardOnly) + `PasteRestoreDelay` prefs.
- Rename: "Paste mode" UI copy becomes "Simulate Keypresses" per Manus; backend enum stays `PasteMode.pasteAtCursor`.

**Scope OUT per locked decision #8**:
- Do NOT choose between CGEvent synthetic keypresses vs incremental Cmd+V for streaming. File backlog: `plans/backlog/streaming-output-delivery-mechanism.md` with trade-offs documented.
- Do NOT wire streaming output into any consumer yet — streaming transcription (FluidAudio streaming ASR) is a separate future slice.

**Open questions to flag**:
- [QUESTION] For streaming, undo semantics: one undo group per session, or per chunk? Affects NSTextView/AppKit editing behaviour.
- [QUESTION] For streaming, rate limit: fixed delay between chunks, or backoff on CGEvent queue pressure?

**Inter-layer dependencies**:
- Requires: Layer 1 (AX permission check delegated).
- Requires: Layer 3 (reads `PasteMode` + `PasteRestoreDelay`).

### Layer 6 — Model selection

**Why**: `ModelRegistry` has one descriptor. `FluidAudioInferenceClient.swift:26` hardcodes `version: .v2`. Parked 3.F work (parakeet-tdt-110m second descriptor) blocked on adapter refactor. User wants multi-model + active selection + swap.

**Scope IN**:
- Types: `ModelDescriptor` (exists) — un-prefix if `SeshatModelDescriptor`. Protocol: `ModelService`.
  - `registeredModels: [ModelDescriptor]`
  - `activeModelID: String` (reads/writes `Preference<String>` key `ActiveModelDescriptor`).
  - `setActive(_ id: String) async throws` — validates registry, downloads if needed, updates preference.
  - `isDownloaded(_ descriptor: ModelDescriptor) -> Bool` — checks managed `models/` dir.
  - `download(_ descriptor: ModelDescriptor, progress:) async throws` — wraps existing `FluidAudioModelDownloader`.
- Refactor `FluidAudioInferenceClient.loadModel(from:)` to take a `version:` derived from the active descriptor, NOT hardcoded `.v2`.
- Migrate: register a second `parakeet-tdt-ctc-110m` descriptor per prior 3.F investigation (SHA `9bc92ead6e8f17eca92a869fd578ae76842b82ba`, 3-artifact fused set, engine `.parakeetTDT`). This is the unblock for 3.F.
- Manus v3 upgrade: register `parakeet-tdt-0.6b-v3-coreml` as a third descriptor and make it default (FluidAudio README now recommends v3).

**Scope OUT**:
- Do NOT build the model-picker UI in this layer — that's Phase 2 Modes tab scope.
- Do NOT touch tokenizer / decoder internals in FluidAudio.

**Open questions to flag**:
- [QUESTION] When user switches active model and the new one isn't downloaded, flow: (a) download in-flight with pill showing progress, (b) error + prompt to download explicitly? Mockup implies (a).
- [QUESTION] What's the default model? Current = v2 (locked in). Manus mockup shows "Parakeet TDT 0.6B" — switch default to v3 on fresh install, or keep v2 for existing users (but locked decision #3 says no migration, so v3 default is fine).

**Inter-layer dependencies**:
- Requires: Layer 2 (storage for `models/` dir), Layer 3 (`Preference<String>` for active ID).
- Blocks: Phase 2 Modes tab (which renders mode cards each referencing a model).

### Layer 7 — Pipeline (post-processing stages)

**Why**: `PostProcessor.clean()` has 2 hardcoded stages (filler removal + basic punctuation). BACKLOG specs a 7-stage pipeline + personal dictionary is about to land as a 3rd stage. No current abstraction for inserting/reordering/testing stages in isolation.

**Scope IN**:
- Protocols: `PostProcessingStage` (conforms `Sendable`) with `apply(_ text: String, context: StageContext) -> String`. `PostProcessingPipeline` composing a `[any PostProcessingStage]` in order.
- Types: `StageContext` — small value-type carrying the session's metadata (recording duration, active mode, ASR confidence if available).
- Default pipeline (today's 2 stages become):
  - `FillerRemovalStage`
  - `BasicPunctuationStage`
- Reserve hooks for backlog'd stages: `PersonalDictionaryStage` (pre-filler), `InverseTextNormalizationStage`, `LLMPolishStage` (Phase 4).
- Pipeline is constructed at `SessionCoordinator` init; active mode can swap pipelines (different modes use different stage chains — e.g., Command mode has no filler removal).
- Rename: `SeshatError.transcriptionFailure` variants if pipeline stages throw — add `.pipelineStageFailed(stageName:underlyingError:)`.

**Scope OUT**:
- Do NOT implement the personal-dictionary stage in this layer — that's its own slice per `plans/backlog/personal-dictionary-plan.md` (if it exists; if not, flag as blocker).
- Do NOT add streaming-safe semantics — stages run at finalize time only. Streaming delivery (Layer 5) bypasses the pipeline until a future "streaming-safe stages" slice.

**Open questions to flag**:
- [QUESTION] Are stages cancellable? If pipeline takes longer than N seconds, cancel + deliver raw text, or always run to completion?
- [QUESTION] How does "active mode" select which pipeline? `ModeDescriptor.pipelineID: String` lookup, or pipeline inline on the mode?

**Inter-layer dependencies**:
- Requires: Layer 6 (active mode selects pipeline variant).

### Layer 8 — Metrics / telemetry

**Why**: Home tab's stat cards (Words this week / Recordings / Mins saved / WPM avg) need these as computed values. Zero current abstraction. All data lives in the SQLite `transcripts` table (3.D) — this layer is a READ-ONLY query service on top.

**Scope IN**:
- Protocol: `MetricsService: Sendable` — read-only queries.
  - `recordingsThisWeek() async throws -> Int`
  - `wordsThisWeek() async throws -> Int`
  - `minsSavedThisWeek() async throws -> Duration` — estimated saved time vs typing baseline.
  - `wpmAverageThisWeek() async throws -> Double` — words per minute of audio duration.
  - `recentTranscriptions(limit: Int = 3) async throws -> [TranscriptEntry]` — for the Home tab's recent-list.
- Live impl: `SQLiteMetricsService` in `SeshatCore` or `SeshatSession`. Wraps `SQLiteTranscriptStore` with per-metric queries.
- **Tokenization for word count**: Unicode word boundaries via `String.enumerateSubstrings(in:options: .byWords)`. Simple, OS-native. No regex.
- **Mins saved**: assumes a baseline typing speed (40 WPM = sane default). Formula: `(wordCount / 40) - audioMinutes`. Clamped ≥ 0. Document the baseline assumption as a `MetricsService.assumedTypingWPM: Int = 40` constant.
- Phase 2 UI: `HomeTabViewModel` injects `any MetricsService`, calls the 4 queries on appear.
- Placeholder handling per locked decision #4: `wordsThisWeek`, `minsSavedThisWeek`, `wpmAverageThisWeek` show "—" if the MVP tokenizer doesn't ship yet — the placeholder is a UI decision, but this layer SHOULD ship all 4 queries real. Author `plans/backlog/home-stats-metrics.md` documenting this fact.

**Scope OUT**:
- Do NOT add a `type`/`kind`/`intent` column to SQLite (locked decision #7). Metrics that need intent-filtering wait for Phase 4.
- Do NOT add telemetry upload / analytics — this is READ-ONLY for the user's own local data. No network.

**Open questions to flag**:
- [QUESTION] "This week" — ISO week (Monday–Sunday) or rolling 7 days? User-locale-sensitive. Default to rolling 7 days to avoid locale bugs.

**Inter-layer dependencies**:
- Requires: Layer 2 (path to SQLite file), 3.D's `SQLiteTranscriptStore` landing.

### Layer 9 — App brand / identity

**Why**: "Seshat" string literal + bundle ID + absent marketing URLs are scattered. One struct consolidates them; a future rebrand flips one file; the "hide links if URL nil" decision lands mechanically.

**Scope IN**:
- Type: `AppBrand` — `enum` (namespace-only) in `SeshatCore` or renamed module.
  - `static let displayName: String = "Seshat"`
  - `static let bundleIdentifier: String = "com.nitkrar.seshat"`
  - `static let logSubsystem: String = bundleIdentifier` (already used by `AppLogger`)
  - `static let websiteURL: URL? = nil`
  - `static let privacyURL: URL? = nil`
  - `static let termsURL: URL? = nil`
  - `static let version: String` — reads `Info.plist` `CFBundleShortVersionString`.
  - `static let buildNumber: String` — reads `CFBundleVersion`.
- Migrate all user-facing `"Seshat"` literals to `AppBrand.displayName`. Menu header, window title, About header, menu bar status-item accessibility label, etc.
- Migrate `"com.nitkrar.seshat"` literals to `AppBrand.bundleIdentifier`. Include: `PasteInjector.seshatBundleIdentifier` (rename to something like `OutputService.selfBundleIdentifier` or just use `AppBrand.bundleIdentifier`), `AppLogger` subsystem, TCC deep-link sites.
- Settings About tab reads `AppBrand.displayName + " " + AppBrand.version + " (" + AppBrand.buildNumber + ")"` per Manus Q.M3.
- Link rows: if `AppBrand.websiteURL == nil`, don't render the row (locked decision #9).

**Scope OUT**:
- Do NOT rename SPM targets (locked decision #2).
- Do NOT touch `Info.plist` bundle identifier — that's packaging.
- Do NOT touch `package.sh` — separate packaging concern.

**Open questions to flag**:
- None expected — this is mechanical.

**Inter-layer dependencies**:
- Requires: Layer 3 (if any of these become user-configurable; they're not today, so strictly no).
- Blocks: Phase 2 About tab rendering.

---

## INDEX.md structure

Include:
- Layer summary table (name, 1-line why, effort estimate S/M/L).
- **Stage 1 parallelisation matrix**: which layers can build in parallel in Stage 1, grouped by directory isolation. Example: { Layer 3, Layer 9 } can run together (different dirs, no shared files); { Layer 1, Layer 2 } can run together; etc.
- **Stage 2 dependency graph** (text table or ASCII):
  - Layer 1 Stage 2 blocks Layer 4 Stage 2.
  - Layer 2 Stage 2 blocks Layers 3, 6, 7, 8 Stage 2.
  - Layer 3 Stage 2 blocks Layers 5, 6 Stage 2.
  - etc.
- **Recommended execution order** with explicit Stage-1 batching:
  - **Wave 1 (Stage 1 in parallel)**: Layer 9 (app brand), Layer 3 (settings), Layer 2 (storage), Layer 1 (permissions). Four subagents, disjoint directories.
  - **Wave 2 (Stage 1 in parallel)**: Layer 6 (model), Layer 7 (pipeline), Layer 8 (metrics), Layer 5 (output). Four subagents; Layer 4 (state store) may run solo after its research is reviewed and approved.
  - **Wave 3 (Stage 2 in sequence per dependency graph)**: migrate consumers one layer at a time, starting with Layer 9 (lowest blast radius) and ending with Layer 4 (highest).
  - **Wave 4 (Stage 3 — Deletion pass)**: one batch commit removing all legacy types after Wave 3 completes.
- **Master step numbering table** (every step across 9 layers × 3 stages, dependencies, estimated commits).
- **Stage 3 — Deletion pass (global)**: the single Stage 3 commit enumerated here, listing every file/type/protocol/key to delete. Implementers run this LAST, after every Stage 2 consumer is migrated.

## Hard rules for the plan writer (codex)

- Write plans, not code. No `swift` snippets longer than 3-line type signatures.
- Cite every fact with `file:line` from the committed tree.
- Do NOT modify any source file.
- Do NOT resolve the "open questions" — surface them as `[QUESTION]` markers.
- Do NOT run `swift build` / `swift test`.
- Commit all 10 files in one commit with subject `trunk: plans/central — 9-layer centralization plan + master index`.

## Hand-off report format

After committing the 10 files, return:
- Commit SHA + subject.
- Word count of each plan file.
- Full layer × step table from INDEX.md.
- List of open questions needing main-session review (grouped by layer).
- List of any existing plan content that becomes stale and should be deleted once this central-layers approach supersedes it (e.g., the existing `plans/PHASE_0_rename.md` if one was produced earlier — mark it deprecated inline, don't delete).
