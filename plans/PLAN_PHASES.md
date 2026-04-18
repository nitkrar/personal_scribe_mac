# Plan: Seshat Phases — Stability → Unified Architecture → Features → Intent

**Authoritative plan for Seshat.** Supersedes and replaces any earlier week- or sprint-based plan files in `plans/` that may appear in git history.

**Goal:** Evolve Seshat in four product-state milestones — first to a stable daily-dictation tool, then to a visually-unified experience, then to a full-featured personal scribe with notes and settings, and finally to an intent-aware assistant. Phase gates are product-state milestones, never calendar dates.

**Phase gate semantics:** Each phase has a definition-of-done. Do not start Phase N+1 work until Phase N's gate is met. Within a phase, tasks are grouped and may run in parallel where noted.

**Architecture premise:**
- Keep existing module layout: `SeshatCore`, `SeshatAudio`, `SeshatTranscription`, `SeshatSession`, `SeshatAppKit`. No new SPM targets.
- Bundle's design language (`AppState`, `AudioEngine`, `IntentClassifier`) is mapped onto existing types — no renames; add new types (`TranscriptStore`, `ModelRegistry`, foundations, intent stubs) in-place.
- Existing code names are canonical; bundle names in the design doc are aspirational labels, not rename directives.

**Source artifacts (read before implementing):**
- `BACKLOG.md` — Week 2 Known Issues table + next-session priorities.
- `plans/seshat_agent_bundle/05_Docs/UX_Audit_Notes.md` — BUG-01 through BUG-10 + 6 GAPs.
- `plans/seshat_agent_bundle/05_Docs/Seshat_UX_Redesign_Proposal.md` — 3-phase roadmap + Intent Layer future.
- `plans/seshat_agent_bundle/05_Docs/Component_Inventory.md` — component dependency tiers.
- `plans/seshat_agent_bundle/00_README/BUILD_ORDER.md` — sprint sequencing.
- `plans/seshat_agent_bundle/01_Foundations/assets/colour_system.png` — dark + light palette.
- `plans/seshat_agent_bundle/01_Foundations/assets/logo_animation_states.png` — logo state frames.
- `plans/SPEC_model_registry_and_base_dir.md` — detailed spec for registry refactor (Phase 1 Group 2).

**Tech stack:** Swift 6, SwiftUI, AppKit, XCTest, FluidAudio 0.13.6 (pinned), CoreML (via FluidAudio). macOS 14+.

---

## Phase Map (top-level)

| Phase | Name | Definition-of-done (product-state milestone) |
|-------|------|--------------------------------------------|
| **1** | Stability + foundational refactors | App is reliable for daily dictation: record → stop → auto-paste works every time. All BACKLOG P0/P1 resolved or explicitly deferred. Registry + base-dir refactor merged. In-memory history available via menu bar popover. Permission UX is informative, not silent. |
| **2** | Unified architecture + visual identity | New design system (theme + quill logo + waveform + core components) shipped. Pill overlay supports the three visibility modes. Menu bar popover redesigned. Dark/light palette applied. Custom app icon in place. |
| **3** | Features + polish | `NotesWindow` + `SettingsWindow` (Modes tab) + `OnboardingWindow`. SQLite-backed transcript history with FTS5 search. Base-dir migration UI. Hotkey customization. Second model descriptor (e.g. 110M) available. |
| **4** | Intent layer + assistant | Intent classifier online. Command Mode response cards. Notes surface as personal knowledge base. llama.cpp / Apple Foundation Models integration. "Ask Seshat" query flow. |

---

# Phase 1 — Stability + Foundational Refactors

**Definition-of-done:** Every item in BACKLOG Week 2 Known Issues is either resolved or explicitly deferred with rationale; app survives a full-day dogfood session; `swift test` green; DMG ships from `/Applications` with no per-launch freeze and reliable click handling.

**Non-goals in Phase 1:** any new design system work, any new windows, any animation polish, any history UI beyond a minimal menu-bar preview.

## Group 1 — Critical bug fixes (Codex handoff — mostly landed)

Commit `1cb665c` ("Fix startup warmup responsiveness and interaction handling") landed most of this group. Remaining work in this group is verification + a missing test case.

### Step 1.1 — `SessionCoordinator.prepareTranscriberInBackground` actor reentry — **DONE**

**Status:** ✅ Committed in `1cb665c`. `Sources/SeshatSession/SessionCoordinator.swift:159` now uses `Task.detached(priority: .background)`. Regression test in `Tests/SeshatSessionTests/SessionCoordinatorPreparationTests.swift`.

**No further implementation work in this step.** Runtime verification is rolled into Step 1.15 dogfood.

### Step 1.1b — Signpost instrumentation for launch-freeze RCA

**Rationale:** BACKLOG's "next-session starter" (line 58-60) explicitly requested `os.signpost` on `SessionCoordinator.prepareTranscriber()`, `FluidAudioTranscriber.performPrepare()`, and `inference.loadModel(from:)` to measure the actual stall location. Step 1.1's `Task.detached` fix only unblocks the actor queue; if FluidAudio's `loadModel` is CPU-starving MainActor via a different path, the freeze could recur. Without measurement, Phase 1 gate's "no per-launch freeze" claim is subjective.

**Files:**
- `Sources/SeshatSession/SessionCoordinator.swift` — wrap `prepareTranscriber()` body.
- `Sources/SeshatTranscription/FluidAudioTranscriber.swift` — wrap `performPrepare()` + around the `inference.loadModel(from:)` call at line ~95.

**Implementation:**
- Add `private let signposter = OSSignposter(subsystem: "com.nitkrar.seshat", category: "prepare")` (requires `import os.signpost` in SeshatCore's `SeshatLogger` or a new dedicated signposter helper).
- Emit `.begin` / `.end` pairs with names `"SessionCoordinator.prepareTranscriber"`, `"FluidAudioTranscriber.performPrepare"`, `"inference.loadModel"`.
- Ensure end is called via `defer` so errors don't drop the interval.

**Verification:** `xcrun xctrace record --template 'Logging' --output /tmp/seshat-launch.trace --launch -- /Applications/Seshat.app/Contents/MacOS/SeshatAppKit` (adjust binary path). Open trace; confirm three intervals visible with plausible durations. Record snapshot timings in `Tests/SeshatTranscriptionTests/ManualTranscriptionVerification.md` under `## Phase 1 Step 1.1b — Launch signposts`.

**Commit subject:** `phase-1 step 1.1b: OSSignposter around prepare + loadModel for launch RCA`

### Step 1.2 — Log prepareTranscriber errors — **DONE (relocated)**

**Status:** ✅ Committed in `1cb665c`. Codex refactored the startup path into `AppStartupCoordinator`; the silent catch no longer exists. Error logging is in place at `Sources/SeshatAppKit/Composition/AppComposition.swift:59` and `Sources/SeshatSession/SessionCoordinator.swift:165`.

**No further implementation work.** If Step 1.6 `SESHAT_BASE_DIR=/dev/null` smoke test surfaces any lingering silent swallow, open a follow-up there.

### Step 1.3 — Menu bar click — **DONE**

**Status:** ✅ Fixed in `1cb665c` by extracting hotkey-install + transcriber-prepare out of `SeshatAppMain.init()` into `AppStartupCoordinator.start()`. `start()` schedules a background Task and returns immediately, so `init()` no longer blocks the MainActor while SwiftUI installs `MenuBarExtra`. User runtime-verified on the DMG built from `1cb665c` (single click + 20-click sanity). A vestigial `await Task.yield()` wrapper was retained for a while under the wrong theory that it was the fix; removed once runtime data confirmed the actual mechanism.

**Sub-steps landed:**
- **1.3a — Runtime verification.** User tested on built DMG: single click opens popover; 20-click sanity passed.
- **1.3b — Regression test.** `testStartupCoordinatorDoesNotBlockInitOnHotkeyInstall` in `Tests/SeshatAppKitTests/MenuBarFlowIntegrationTests.swift` asserts `init()` does not synchronously block on hotkey install. Weak proxy (doesn't observe MenuBarExtra directly) — 1.3a remains ground truth.

**Commit subjects:**
- `phase-1 step 1.3b: MenuBarFlow ordering regression test`
- (later) `phase-1 step 1.3 cleanup: remove vestigial Task.yield() from SeshatAppMain.init`

### Step 1.4 — Pill click end-to-end tests — **PARTIAL**

**Status:** ✅ Committed in `1cb665c`. Test A (tap fires when enabled) and Test B (tap suppressed when disabled) are in `Tests/SeshatAppKitTests/PillOverlayPresenterTests.swift:36-64`. **Test C missing.**

Remaining work:
- **1.4b — Add Test C.** `mouseDown` → simulated 10pt drag (multiple `mouseDragged` events crossing the 4pt threshold) → `mouseUp`. Assert `onTap` does NOT fire; `onMouseDragged` callback does. Use the same `ClickThroughHostingView` stub pattern as tests A/B. The state-machine-level drag test already exists at `PillOverlayPresenterTests.swift:17-34`; this one covers the end-to-end hosting-view path.

**Commit subject:** `phase-1 step 1.4b: add drag-suppresses-tap end-to-end test`

## Group 2 — Model Registry + Configurable Base Directory

Follow `plans/SPEC_model_registry_and_base_dir.md` step-for-step. Summary only here; see spec for code bodies.

### Step 1.5 — `ModelRegistry.swift` (new)
- New file: `Sources/SeshatCore/ModelRegistry.swift`.
- Tests: `Tests/SeshatCoreTests/ModelRegistryTests.swift` — descriptor round-trip, default id, URL resolution.
- **Commit subject:** `phase-1 step 1.5: ModelRegistry with Parakeet 0.6B v2 descriptor`

### Step 1.6 — Configurable `SeshatConfig` base directory
- Modify `Sources/SeshatCore/Config.swift`.
- Env var `SESHAT_BASE_DIR` > `UserDefaults("SeshatBaseDirectoryPath")` > default `~/Library/Application Support/Seshat/`.
- Helpers: `baseDirectory()`, `modelsDirectory()`, `modesDirectory()`, `recordingsDirectory()`, `directory(for: descriptor)`.
- Tests: `Tests/SeshatCoreTests/SeshatConfigTests.swift`. **Run test target with `-parallel-testing-enabled NO`** (XCTest parallelism + `nonisolated(unsafe) testingBaseDirectoryOverride` is a known race; until we migrate to per-test instance config, force serial).
- Each test that mutates `testingBaseDirectoryOverride` or `SeshatBaseDirectoryPath` MUST `defer { UserDefaults.standard.removeObject(forKey: "SeshatBaseDirectoryPath"); SeshatConfig.testingBaseDirectoryOverride = nil; unsetenv("SESHAT_BASE_DIR") }` for isolation.

**Caveat to flag in code comment in `Config.swift`:**
> The `UserDefaults("SeshatBaseDirectoryPath")` override path only takes effect when the app runs from the packaged `.app` bundle with `CFBundleIdentifier = com.nitkrar.seshat`. When running via `swift run`, the executable's bundle identifier is the SPM default (empty or `SeshatAppKit`), so `defaults write com.nitkrar.seshat SeshatBaseDirectoryPath …` from a terminal is a silent no-op for the dev binary. The env var `SESHAT_BASE_DIR` works in both contexts. Unit tests pass because xctest runs in its own process domain and the same `UserDefaults.standard` read/write happens in-process.

**Manual verification addition:** after the unit-test path passes, document a packaged-app verification:
```
defaults write com.nitkrar.seshat SeshatBaseDirectoryPath /tmp/seshat-ud-test
open /Applications/Seshat.app
# verify models land under /tmp/seshat-ud-test/models/parakeet-tdt-0.6b-v2/
defaults delete com.nitkrar.seshat SeshatBaseDirectoryPath
```
Record outcome in `Tests/SeshatCoreTests/ManualConfigVerification.md`.

**Caveat to flag in code comment:** the `nonisolated(unsafe)` on `testingBaseDirectoryOverride` only survives if test parallelism is off. Add a `#warning` that triggers if `SWIFT_DETERMINISTIC_HASHING` is unset to nudge future maintainers.

**Commit subject:** `phase-1 step 1.6: configurable base directory (env var + UserDefaults)`

### Step 1.7 — `FluidAudioTranscriber` + downloader take `ModelDescriptor`
- Delete `enum ParakeetArtifact`; replace with descriptor-driven flow.
- `FluidAudioTranscriber.init(descriptor: ModelDescriptor = ModelRegistry.parakeetTDT06Bv2, logger:)`.
- Expose `public var activeModelId: String { descriptor.id }` for test + future settings UI use.
- `FluidAudioInferenceClient` — verified clean (no hardcoded model refs); no changes required.
- Staging dir signature: `stagingDirectory(base:descriptor:)`, suffix `"\(descriptor.id)-staging"`.

**Ordering dependency:** Codex's work landed in commit `1cb665c`, which already modified `FluidAudioTranscriber.swift` (including the staging-dir cleanup at `FluidAudioTranscriber.swift:220-251`). This step rebases on top of that committed state. Verify via `git log --oneline -- Sources/SeshatTranscription/FluidAudioTranscriber.swift` before starting; if new commits have landed since `1cb665c`, re-read the file before editing.

**Commit subject:** `phase-1 step 1.7: FluidAudio* take ModelDescriptor`

### Step 1.8 — Smoke test with live model
- `rm -rf ~/Library/Application\ Support/Seshat/models` → `swift run` → confirm fresh download + transcription works.
- `SESHAT_BASE_DIR=/tmp/seshat-test swift run` → confirm models land in `/tmp/seshat-test/models/parakeet-tdt-0.6b-v2/`.
- Record outcome in `Tests/SeshatTranscriptionTests/ManualTranscriptionVerification.md` under `## Phase 1 Step 1.8`.

**Commit subject:** `phase-1 step 1.8: registry + base dir manual verification`

## Group 3 — Permission detection (backend-only; visible UX deferred to Phase 2)

Bundle v3 replaces the menu bar SwiftUI popover with a native `NSMenu`. Building SwiftUI permission banners now would be throwaway work. Phase 1 therefore ships permission **detection + logging** only; visible permission feedback (as NSMenu items) lands in Phase 2 cross-cutting alongside the NSMenu build — once, not twice.

Dogfood UX tradeoff: a user whose hotkey silently fails in Phase 1 will need to check `log stream --predicate 'subsystem == "com.nitkrar.seshat"'` to diagnose. Acceptable for dogfood (you, not a stranger).

### Step 1.9 — Input Monitoring permission detection (backend + log only)

**File:** new `Sources/SeshatCore/PermissionStatus.swift` + modify `Sources/SeshatAppKit/Hotkey/GlobalHotkeyMonitor.swift`.

- Add enum `InputMonitoringPermissionState { case granted, denied, notDetermined }` plus a `PermissionProbing` protocol for test injection.
- Detect via `IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)` only. **Do not use `CGPreflightListenEventAccess`** — that API surfaces the Accessibility TCC bucket, not Input Monitoring, and will silently mis-report granted when AX is granted but IM is denied.
- `import IOKit.hid` in `PermissionStatus.swift`. This is a new dependency for `SeshatCore` — verify IOKit is already transitively linked via the existing `AppKit` dependency graph; if not, add an explicit `.linkedFramework("IOKit")` to the `SeshatCore` target in `Package.swift`.
- `IOHIDCheckAccess` returns `.unknown` until the app has attempted to create an event tap or monitor at least once. Gate detection on "after first `NSEvent.addGlobalMonitorForEvents` attempt"; treat pre-attempt as `.notDetermined`.
- `GlobalHotkeyMonitor.start()` logs a warning at `.error` level if `NSEvent.addGlobalMonitorForEvents` returns `nil`, with a concrete pointer to Phase 2's upcoming NSMenu remediation: `"Global hotkey monitor failed to register — likely Input Monitoring permission denied. Visible remediation will land with Phase 2 NSMenu; until then, grant access in System Settings → Privacy & Security → Input Monitoring and restart."`.
- **No UI changes in Phase 1.** The existing `MenuBarScene.swift` popover is untouched.

**Tests:** `Tests/SeshatCoreTests/PermissionStatusTests.swift` — unit test the state-derivation logic using the `PermissionProbing` protocol + mock. Do NOT unit-test `IOHIDCheckAccess` directly. Also test that a `.nilReturnedFromMonitor` signal results in the expected log output via a mock logger.

**Deferred to Phase 2:** NSMenu item that surfaces the state visibly (e.g. disabled "⚠️ Input Monitoring required — click to open Settings"), with correct macOS 14 vs 15 URL scheme branching. Tracked in the Phase 2 cross-cutting items list below.

**Commit subject:** `phase-1 step 1.9: Input Monitoring detection + warn log (no UI)`

### Step 1.10 — Mic permission inline banner — **REMOVED**

**Status:** ❌ Deleted from Phase 1. The existing `MenuBarScene.swift:17-30` already has a `case .denied:` switch arm with an "Open Settings" button — functional if not beautiful. Building a new SwiftUI banner above it would be throwaway work given Phase 2's NSMenu replaces the entire popover. Mic permission UX improvements land in Phase 2 as an NSMenu item alongside Input Monitoring's.

## Group 4 — Transcript history primitive (plumbing only, UI stays minimal)

### Step 1.11 — `TranscriptStore` actor in `SeshatCore` (JSON-lines persistence + in-memory ring)

**File:** `Sources/SeshatCore/TranscriptStore.swift` (new).

**Architecture alignment:** bundle v3 BUG-06 mandates on-disk persistence ("SQLite or JSON on disk"). Phase 1 ships JSON-lines (newline-delimited JSON) — simplest persistence that Phase 3 `NotesWindow` + SQLite migration can ingest without a schema negotiation.

- `struct TranscriptEntry: Sendable, Equatable, Identifiable, Codable { id, text, createdAt }`.
- `actor TranscriptStore` — in-memory ring buffer, **capacity 500 default** (fast reads for future menu-bar-less dogfood inspection).
- Methods: `append(_:)`, `all()`, `latest()`.
- **Persistence path:** `SeshatConfig.recordingsDirectory().appendingPathComponent("transcripts.jsonl")`. Each `append()` encodes the entry to JSON and atomically appends a single line (newline-terminated) via `FileHandle(forUpdatingAtPath:)` + `seekToEndOfFile()` + `write(_:)` + `synchronize()`. Wrap writes in a `do/catch` that logs failures at `.error` but does not throw out of `append()` — store semantics prioritise not losing the in-memory entry if disk is full.
- **Load on init:** if `transcripts.jsonl` exists at the resolved path, stream the last ~500 lines (`FileHandle` + chunked reverse read, or simple `String(contentsOf:)` + `.split(separator: "\n").suffix(capacity)`) and hydrate the ring. Corrupt lines: skip individually, log count at `.warning`.
- **Capacity eviction:** when count > capacity, drop oldest from the ring. The on-disk file retains all history — eviction is ring-only. Log at `.info` once per session when first eviction hits.
- Phase 3 SQLite migration reads the same `transcripts.jsonl` as its import source, then leaves it in place as a rollback artifact.

**Tests:** `Tests/SeshatCoreTests/TranscriptStoreTests.swift` — round-trip, ring eviction, first-eviction log signal via a mock logger, disk-write failure path (simulate via a read-only directory), init-from-existing-file round-trip, corrupt-line-skip behaviour.

**Commit subject:** `phase-1 step 1.11: TranscriptStore — JSONL persistence + 500-entry in-memory ring`

### Step 1.12 — Wire `TranscriptStore` through `SessionCoordinator`

**Files:** `Sources/SeshatSession/SessionCoordinator.swift`, `Sources/SeshatAppKit/Composition/AppComposition.swift`.

- Inject `TranscriptStore` into `SessionCoordinator.init`.
- On successful transcription, `await store.append(TranscriptEntry(text: result, createdAt: .now))`.
- **Do NOT publish `latestTranscript` to `MenuBarSceneModel`.** Bundle v3 BUG-06 says the menu bar popover shows no transcript content — history is accessed only via the (Phase 3) `NotesWindow`. Phase 1 stores silently; no UI surfacing.

**Single-source-of-truth rule:** the store (in-memory ring + on-disk JSONL) is the sole history record in Phase 1. No cached copies in view models.

**Tests:** extend existing `SessionCoordinatorTests` with a "transcription appends to store" case. Verify no `MenuBarSceneModel` mutations originate from the store-observation path.

**Commit subject:** `phase-1 step 1.12: plumb TranscriptStore through SessionCoordinator (store-only, no UI surfacing)`

### Step 1.13 — Build info in popover (dogfood attribution only)

**File:** `Sources/SeshatAppKit/MenuBar/MenuBarScene.swift`

**Scope:** per bundle v3 BUG-06, the menu bar popover shows no transcript content in Phase 1 or beyond. This step adds only the build-info caption — a single line so dogfood bug reports can attribute to a specific build. The existing popover contents (Record button + existing `permissionState` switch arms including "Open Settings" for denied-mic case) stay as-is. No SwiftUI banners are added; Step 1.9 is backend-only; Step 1.10 was removed.

- Render at the bottom of the popover (below any existing content, caption-sized secondary text): `Text("v\(CFBundleShortVersionString) · \(shortGitSHA)")`.
- `shortGitSHA` comes from a build-time generated constant. Add `Scripts/write-build-info.sh` that writes `Sources/SeshatCore/BuildInfo.generated.swift` with the output of `git rev-parse --short HEAD`. Wire into `Scripts/package-dev-dmg.sh` as a pre-compile step. Add `BuildInfo.generated.swift` to `.gitignore`.

**Dogfood UX note to include in `BACKLOG.md` Phase 1 dogfood log preamble:** "Phase 1 has no visible transcript history. To inspect past transcripts, open `<SeshatConfig.baseDirectory()>/recordings/transcripts.jsonl` in a text editor. Phase 3 `NotesWindow` replaces this workaround."

**Commit subject:** `phase-1 step 1.13: build info caption in popover`

## Group 5 — Phase 1 gate

### Step 1.14 — Backlog reconciliation

Copy the table below verbatim into `BACKLOG.md` under a new `## Phase 1 closures` section. Before committing, verify every row's claim: commit SHAs exist, referenced mockup files exist at the cited paths, and no claim contradicts the actual code or plan state. Any drift blocks the Phase 1 gate.

| BACKLOG ID | Closure source | Note |
|------------|---------------|------|
| P0 #1 (app unresponsive at launch) | Phase 1 steps 1.1 + 1.1b + 1.3a | `Task.detached` landed in `1cb665c`; signposts + runtime verify pending |
| P0 #2 (download hijacks recording pill) | Commit `1cb665c` | Pre-landed by Codex in `Sources/SeshatAppKit/Overlay/PillOverlayViewModel.swift:26-36` (recording state wins) |
| P0 #5 (pill & menu bar clicks dead) | Commit `1cb665c` + Phase 1 steps 1.3a, 1.3b, 1.4b | Pill half pre-landed (DraggablePanel mouseDown/mouseUp); menu bar half is `Task.yield()` in `SeshatAppMain.swift:78`, runtime verification + regression test pending |
| P1 #3 (every rebuild re-downloads 400MB) | Commit `1cb665c` | Pre-landed in `Sources/SeshatTranscription/FluidAudioTranscriber.swift:220-251` (only staging dir wiped on failure) |
| P1 #8 (idle pill draggable) | Commit `1cb665c` | Pre-landed — single `DraggablePanel` reused across all visibility states |
| P1 #4 (idle dot visual) | Deferred → Phase 2 | Mockup answers per `plans/seshat_agent_bundle/01_Foundations/assets/logo_animation_states.png` ("Idle" tile) and `plans/seshat_agent_bundle/03_Surfaces/PillOverlayWindow/architecture.png` (Mode 1) |
| P1 #9 (recording pill too big) | Deferred → Phase 2 | Mockup answers per `plans/seshat_agent_bundle/03_Surfaces/PillOverlayWindow/command_mode_states.png` (180×34 pill dimensions) |
| P2 #6 (pulsing-dots animation) | Deferred → Phase 2 | Mockup prescribes animated waveform per `plans/seshat_agent_bundle/03_Surfaces/PillOverlayWindow/recording_states.png` + `logo_animation_states.png` ("Listening"/"Transcribing" tiles) |
| P3 #7 (LSUIElement emergency quit) | Deferred → Phase 3 | No mockup coverage; gated behind Shortcuts tab in `settings_modes.png` |

**Commit subject:** `phase-1 step 1.14: reconcile backlog against Phase 1 closures`

### Step 1.15 — Dogfood DMG + full-day trial

1. Rebuild DMG via `Scripts/package-dev-dmg.sh` (existing). Document any env vars the script reads at invocation.
2. Install to the canonical path `/Applications/Seshat.app`. Go through Gatekeeper approval once. **Do not run the app from the DMG's mounted volume** — the macOS TCC ad-hoc-path quirk (see `project_tcc_ad_hoc_quirk.md` memory) gives per-path TCC records, so permissions granted to the DMG copy would not transfer to `/Applications`.
3. Use for a full work day once all prior Phase 1 steps are merged. Log frictions in `BACKLOG.md` under a new "## Phase 1 dogfood log" section.
4. Any P0 discovered during dogfood → fix before starting Phase 2.

**Commit subject:** `phase-1 step 1.15: DMG ship + dogfood log seeded`

**Phase 1 Gate — objective thresholds (all must hold):**
1. All steps 1.0–1.15 merged; `swift test` fully green.
2. During a single dogfood session, `TranscriptStore.all().count >= 10` — confirms record → transcribe → store works repeatedly.
3. `log stream --predicate 'subsystem == "com.nitkrar.seshat"' --last 1d` shows zero crash signatures and zero uncaught error-level messages tagged as "prepare failed" or "transcription failed" during the dogfood window.
4. Manual 20-click menu-bar sanity test passes: popover opens every click, no skipped clicks in the sequence. Record outcome in the dogfood log with a timestamp.
5. Dogfood log entry exists in `BACKLOG.md` under `## Phase 1 dogfood log` with EITHER a ≥5-item friction list OR the explicit line `"zero frictions observed"`.
6. `BACKLOG.md` contains the marker line `Phase 1 gate met.` — this is the literal string Phase 2 kickoff looks for.
7. Signpost traces from Step 1.1b show cold-launch `prepareTranscriber` completes in under 5 seconds on the dogfood hardware, OR the log records a measured outlier with a hypothesised cause.

Only after all 7 hold: start Phase 2.

---

# Phase 2 — Unified Architecture + Visual Identity

Phase 2 adopts the bundle's sprint + agent assignments from `plans/seshat_agent_bundle/00_README/BUILD_ORDER.md` verbatim. Do not re-invent a different slicing — the bundle's slicing is the contract for parallel execution.

## Shared Files — NEVER Duplicate, Always Import

These files are the single source of truth. If a Phase 2 (or Phase 3) step needs any of their behaviour, it MUST `import` — not re-declare, not copy, not inline. If a step finds the shared file does not yet exist, the step BLOCKS on the owning agent instead of forking a parallel implementation.

| File | Owner sprint / agent | Consumer sprints |
|------|----------------------|------------------|
| `Sources/SeshatAppKit/Theme/SeshatTheme.swift` | Sprint 1 / Agent 1 | All Phase 2 + Phase 3 views |
| `Sources/SeshatAppKit/Components/SeshatLogoView.swift` | Sprint 1 / Agent 1 | Pill, Onboarding, Notes (menu bar status item uses a **static `NSImage` template asset** exported from the quill mark, NOT a live `SeshatLogoView` — per `03_Surfaces/MenuBarMenu/IMPORTANT.md`) |
| `Sources/SeshatAppKit/Components/WaveformView.swift` | Sprint 1 / Agent 1 | Pill, Notes (linked recordings) |
| `Sources/SeshatCore/TranscriptStore.swift` (exists — built Phase 1 step 1.11) | Phase 1 | All surfaces |
| `AppState` role — mapped onto existing `Sources/SeshatSession/SessionCoordinator.swift` + `Sources/SeshatAppKit/MenuBar/MenuBarSceneModel.swift` | Phase 1 | All surfaces |

Duplication audit runs before every Phase gate: `grep -r "Color(hex:"` outside `SeshatTheme.swift`, `grep -r "feather"` outside `SeshatLogoView.swift`, etc. Any hit fails the gate.

## Bugs with mockup-prescribed answers (no design discussion — implement per mockup)

The mockups are the spec. Phase 2 executors MUST NOT re-open design debate on any row below; the answer is in the cited file. Any deviation requires a user sign-off on the record before implementation.

| Bug ID | Mockup file(s) — paths relative to repo root | Prescribed answer |
|--------|----------------------------------------------|-------------------|
| BACKLOG P1 #4 / UX audit BUG-10 (idle pill visual) | `plans/seshat_agent_bundle/01_Foundations/assets/logo_animation_states.png` (Idle tile) + `plans/seshat_agent_bundle/03_Surfaces/PillOverlayWindow/architecture.png` (Mode 1 row) | Compact capsule: quill + flat wave + "Idle" label. NOT a bare dot. |
| BACKLOG P1 #9 (recording pill too big) | `plans/seshat_agent_bundle/03_Surfaces/PillOverlayWindow/command_mode_states.png` PANEL 1 | 180×34 pill; quill + waveform + elapsed time + pause/stop controls. |
| BACKLOG P2 #6 / UX audit BUG-05 (pulsing-dots animation) | `plans/seshat_agent_bundle/03_Surfaces/PillOverlayWindow/recording_states.png` + `plans/seshat_agent_bundle/01_Foundations/assets/logo_animation_states.png` | Listening = animated red waveform through quill. Transcribing = flat wave + quill with ink-drip. Delete `PulsingDot` entirely. |
| UX audit BUG-08 (missing `.transcribing` state visual) | `plans/seshat_agent_bundle/03_Surfaces/PillOverlayWindow/light_mode_states.png` PANEL 3 + `logo_animation_states.png` "Transcribing" tile | Flat waveform + quill with ink drip + "Transcribing…" label. On completion, transition to green "Copied to clipboard" toast that fades after 2s. |
| UX audit BUG-10 (pill always-visible, no hide) | `plans/seshat_agent_bundle/03_Surfaces/PillOverlayWindow/architecture.png` (three rows: Always On / Auto-show / Hidden) | Three visibility modes user-selectable: **Always On** / **Auto-show (default)** / **Hidden**. Phase 2 persists choice in `UserDefaults` (key `SeshatPillVisibilityMode`, default `"auto-show"` on first launch); Settings UI for toggling lands in Phase 3. **Invariant — at least one user-reachable surface MUST always be visible.** The menu bar status item and the pill cannot both be hidden simultaneously. In Phase 2 the status item is always-visible (no toggle yet exists), so the invariant holds by construction. Phase 3 Settings UI, if it ever introduces a "hide menu bar" toggle, MUST refuse to apply it when pill mode = Hidden (and vice versa); show an inline explanation: *"One surface must stay visible so you can reach the app."* |
| UX audit GAP-01 (no app icon) | `plans/seshat_agent_bundle/01_Foundations/assets/logo_dark.png`, `logo_light.png` | Diagonal quill mark; dark + light variants; menu-bar monochrome template variant. |
| UX audit GAP-05 (no dark/light mode awareness) | `plans/seshat_agent_bundle/01_Foundations/assets/colour_system.png` + `plans/seshat_agent_bundle/03_Surfaces/PillOverlayWindow/light_mode_states.png` | Explicit hex palettes per theme; all Phase 2 surfaces support both; light-mode pill variants drawn. |
| UX audit BUG-04 (MenuBarScene plain-text, no visual hierarchy) | `plans/seshat_agent_bundle/03_Surfaces/MenuBarMenu/IMPORTANT.md` (authoritative) | Replace `MenuBarExtra` + SwiftUI popover with **native `NSMenu`**. Items: active Mode name (non-interactive header), Start/Stop Recording ⌥⌘, History (opens NotesWindow), Settings (opens SettingsWindow), separator, Quit Seshat. No SwiftUI components inside the menu. Status item icon = static NSImage template from the quill mark. |

### Bugs that still need plan-level discussion (no mockup answer)

- **BACKLOG P1 #8 (idle pill drag affordance)** — mockup silent. Already handled by Phase 1 (pre-landed in `1cb665c`; single `DraggablePanel` drags in all states).
- **UX audit BUG-03 (in-menu permission feedback, not onboarding)** — mockup covers onboarding only; in-menu remediation is handled by Phase 2 cross-cutting NSMenu permission items alongside BUG-04's NSMenu build.
- **UX audit BUG-07 (clipboard clobber timing)** — no mockup; Phase 3 Settings (3.H).
- **BACKLOG P3 #7 (emergency quit)** — no mockup; Phase 3 Shortcuts (3.I).

## Sprint 1 — Foundations (no dependencies on each other)

| Agent | Owns | Files (new) |
|-------|------|-------------|
| **1** (UI primitives) | `SeshatLogoView`, `WaveformView`, `StatusPill`, `TagChip`, `ActionButton`, `SeshatTheme` | `Sources/SeshatAppKit/Theme/SeshatTheme.swift`, `Sources/SeshatAppKit/Components/{SeshatLogoView,WaveformView,StatusPill,TagChip,ActionButton}.swift` |
| **2** (state & audio plumbing) | Audio-level RMS stream from `AVAudioCaptureService` → `SessionCoordinator` → UI; `IntentClassifier` protocol stub (Phase 4 placeholder, zero logic); update `SessionCoordinator` to publish audio level at ~10 Hz | `Sources/SeshatCore/IntentClassifier.swift` (protocol + no-op impl), modifications to `Sources/SeshatAudio/AVAudioCaptureService.swift`, `Sources/SeshatSession/SessionCoordinator.swift` |

**Agent 1 and Agent 2 work in parallel.** Zero file overlap. Both must complete before Sprint 2.

## Sprint 2 — Composites + Pill (depends on Sprint 1)

**Agents 1 and 2 have no mutual dependency inside Sprint 2 — they run fully in parallel.** Agent 1's `PillOverlayWindow` depends on `ResponseCard` (also owned by Agent 1, built first); Agent 2's composites do not depend on anything Agent 1 produces in Sprint 2.

| Agent | Owns | Files (new) |
|-------|------|-------------|
| **1** (pill rewrite) | **First: `ResponseCard` (no external dependencies).** Then: rewrite `PillOverlayView` + `PillOverlayPresenter` for three visibility modes (always-on / auto-show / hidden); integrate `SeshatLogoView` + `WaveformView` + the newly-built `ResponseCard`; pill uses champagne palette via `SeshatTheme`. | `Sources/SeshatAppKit/Components/ResponseCard.swift`; modifications to `Sources/SeshatAppKit/Overlay/*.swift`; new `Sources/SeshatAppKit/Overlay/PillVisibilityMode.swift` |
| **2** (composite components) | `TranscriptRow`, `ModeCard`, `AudioPlayerThumbnail` — reference `plans/seshat_agent_bundle/02_Composites/component_map.png`. | `Sources/SeshatAppKit/Components/{TranscriptRow,ModeCard,AudioPlayerThumbnail}.swift` |

**Bundle v3 inconsistency note (TagChip ownership):** `plans/seshat_agent_bundle/00_README/BUILD_ORDER.md` Sprint 2 Agent 2 in v3 also lists `TagChip`, but `TagChip` is listed as a foundation in Sprint 1 Agent 1 (and in `Component_Inventory.md` row 4). This plan follows `Component_Inventory.md` as authoritative: **`TagChip` is built by Sprint 1 Agent 1** (foundations), NOT re-built in Sprint 2. If the bundle is re-issued with this corrected, no plan change needed. If an executing agent sees `TagChip` listed in both the bundle's BUILD_ORDER and this plan's Sprint 1 table, build in Sprint 1 and ignore the BUILD_ORDER Sprint 2 mention.

**Conflict watchpoints:** both agents consume `SeshatTheme` + `SeshatLogoView` + `WaveformView` but neither MODIFIES them. If a theme token is missing, Sprint-2 agent files an issue against Sprint 1; does not inline. Agent 2 must not touch `ResponseCard.swift` (Agent 1's pre-req file).

## Sprint 3 — Surfaces (depends on Sprint 2)

Moved to Phase 3 (see below). Sprint 3's surfaces (`NotesWindow`, `SettingsWindow`, `OnboardingWindow`, native `MenuBarMenu` redesign) are features, not stability work, so they graduate.

Phase 2 itself closes when Sprint 1 + Sprint 2 land and the existing menu bar popover + pill surfaces are rewired to use the new design system. The full `NotesWindow` / `SettingsWindow` / `OnboardingWindow` are Phase 3.

## Phase 2 cross-cutting items (apply within Sprint 1 or Sprint 2, NOT a parallel agent assignment)

These belong to whichever sprint's owning agent can pick them up:

- **Dark/light mode wiring** via `@Environment(\.colorScheme)` + `SeshatTheme.Palette.for(scheme:)`. Owner: Sprint 1 / Agent 1 (co-located with `SeshatTheme`).
- **Asset catalog setup** — `.process("Resources")` added to `SeshatAppKit` target in `Package.swift`; asset catalog at `Sources/SeshatAppKit/Resources/Assets.xcassets/`. Owner: Sprint 1 / Agent 1 (co-located with `SeshatLogoView`). Additionally export the static menu-bar-status-item template image (18×18pt @2x, monochrome) to `Assets.xcassets/StatusBarIcon.imageset/` with `Render As = Template Image` for macOS auto-tinting.
- **Custom `.icns` app icon** generated from the finalised `SeshatLogoView`. Owner: Sprint 2 / Agent 1 (after logo stabilises).
- **Menu bar rewrite (native `NSMenu`)** per `03_Surfaces/MenuBarMenu/IMPORTANT.md`. Owner: Sprint 2 / Agent 2 (after composite components land). Replaces `MenuBarExtra` + SwiftUI popover in `SeshatAppMain.swift` and `MenuBarScene.swift`. Delete both `MenuBarScene.swift` and `MenuBarSceneModel.swift`'s popover-specific view state; keep only the state needed by the status item (recording/idle for icon swap). Bind `Start/Stop Recording` to `SessionCoordinator.toggle()`. History + Settings items open their respective windows (stub with a placeholder `NSAlert("Coming in Phase 3")` handler; wire to real windows when Phase 3 builds them).
- **Permission state as NSMenu items** alongside the NSMenu rewrite. Owner: same as menu bar rewrite. For each permission (Mic via `AVCaptureDevice.authorizationStatus`, Input Monitoring via `IOHIDCheckAccess` from Phase 1 Step 1.9), if `!granted`, prepend a disabled menu item: `⚠️ Microphone access required — open Settings` / `⚠️ Input Monitoring required — open Settings`. Clicking (requires making the disabled item actionable via a custom NSMenuItem target/action) opens System Settings. Use macOS-14 URL scheme with `#available(macOS 15, *)` branch. This closes UX audit BUG-03 alongside BUG-04.
- **Status item icon animation:** on recording, swap the status item's NSImage from the idle quill template to an animated variant (or cycle between two frames). Static-image cycle is sufficient — do NOT attempt a live SwiftUI waveform inside the status item.
- **`StatusPill` scope:** `StatusPill` is consumed by `SettingsWindow` (Phase 3) and `OnboardingWindow` (Phase 3) only. Do NOT use it in the menu bar — the menu bar is native `NSMenu` (no SwiftUI). Do NOT use it in the pill overlay — the pill uses `SeshatLogoView` + `WaveformView` + raw text. Per bundle v3 `Component_Inventory.md`.
- **`SeshatLogoView` scope:** consumed by the pill overlay, `OnboardingWindow`, and `NotesWindow`. Do NOT instantiate in the menu bar — status item icon is a static template `NSImage` exported from the quill mark, NOT a live SwiftUI view. Per bundle v3 `03_Surfaces/MenuBarMenu/IMPORTANT.md`.
- **Existing menu bar popover rewire** — replace inline `Text("Seshat — …")` + raw `Button` with a SwiftUI popover surface that imports `StatusPill` + `ActionButton` + the composite `TranscriptRow` preview. Owner: Sprint 2 / Agent 2 (after `TranscriptRow` is built).

## Key decisions to lock in at Phase 2 kickoff (not now)

- Vector `SeshatLogoView` vs. raster-in-asset-catalog. Vector wins for app icon generation; raster is simpler. Defer until kickoff.
- Snapshot testing library: add `pointfreeco/swift-snapshot-testing`? Or rely on `#Preview` + manual verification? Cost/benefit at kickoff.
- `WaveformView` draw frequency: `TimelineView(.animation)` at 60 Hz vs. on-demand redraw keyed to audio level. Prefer on-demand for always-on idle pill.

## Phase 2 definition-of-done

- All five shared files exist and are imported by every consumer (duplication audit passes).
- Old `PillOverlayView.PulsingDot × 3` is deleted; waveform replaces it.
- Menu bar implemented as native `NSMenu` per `plans/seshat_agent_bundle/03_Surfaces/MenuBarMenu/IMPORTANT.md` (supersedes the historical `menu_design.png`). Items: active Mode name / Start-Stop Recording ⌥⌘ / History / Settings / separator / Quit. Zero SwiftUI components inside the menu. Permission items render when required.
- Pill supports three visibility modes (always-on / auto-show / hidden) with a toggle in `MenuBarSceneModel` (Settings UI comes Phase 3 — for Phase 2 gate, toggle lives in `UserDefaults` only).
- Custom `.icns` in DMG.
- Dark mode first; light mode parity tracked as an explicit follow-up within-phase, not punted to Phase 3.

---

# Phase 3 — Features + Polish

| Group | Deliverable | Depends on |
|-------|-------------|------------|
| 3.A | `SettingsWindow` with General / AI Models / Modes / Shortcuts / Advanced tabs (Modes tab first — introduces `ModeDescriptor`). **Must enforce the visibility invariant** — when General tab builds any visibility toggle (pill mode or menu bar visibility), reject the combination that leaves both hidden; unit test `test_applyVisibilityConfig_rejectsBothHidden` asserts the setter returns a `.conflict` error when both surfaces would go away. | Phase 2 gate |
| 3.B | `NotesWindow` (sidebar + editor + context panel) — auto-ingest transcripts, manual edit, tagging, FTS5 search | 2.C + 3.A (Modes) |
| 3.C | `OnboardingWindow` — first-run permission flow with optional Accessibility step | 2.B |
| 3.D | SQLite `TranscriptStore` migration: GRDB.swift, FTS5 virtual table, Atomic migration from in-memory on first launch | 1.11 |
| 3.E | `BaseDirectoryMigrator`: moves models/modes/recordings when user changes base in Settings | 1.6, 3.A |
| 3.F | Second model descriptor populated: `parakeet-tdt-110m` for lower-RAM devices | 1.5, 3.A (model selection UI) |
| 3.G | Hotkey customization in Settings (Shortcuts tab). Detect collision with system shortcuts. | 3.A |
| 3.H | BUG-07 clipboard clobber timing — configurable paste-restore delay default 0.5s | 3.A |
| 3.I | Triple-tap ⌥ emergency quit (BACKLOG P3 #7) | 1.9 (permission detection plumbing reused) |

**Phase 3 definition-of-done:** a new user can install the DMG, complete onboarding, select a mode, record for weeks, and search all past transcripts.

---

# Phase 4 — Intent Layer + Assistant (Future)

Scope sketch only — revisit after Phase 3 ships and dogfood feedback on intent-style flows accumulates.

- `IntentClassifier` — NLEmbedding-based first, escalate to llama.cpp local LLM when ambiguous.
- Command Mode pill response cards (query answer / action confirmation / dictation).
- "Ask Seshat" query flow wired to `NotesWindow` FTS5 + embedding lookup.
- llama.cpp embed, Apple Foundation Models integration, cloud Whisper optional.
- Action Dispatcher (NSWorkspace + app-specific APIs).

---

## Cross-cutting rules (apply to every phase)

1. **TDD required.** Every feature/bug step starts with a failing test. UI-only changes that can't be XCTest'd require an entry in a `ManualVerification.md` file before the change is marked shipped (memory rule).
2. **Don't overclaim.** "Built" ≠ "shipped". Only runtime verification via DMG counts as done (memory rule).
3. **Minimise rebuild friction.** Batch related changes so a phase produces ~3 rebuild cycles, not N (memory rule).
4. **Don't flip-flop.** Parakeet/FluidAudio choice stays unless new technical data overrides it (memory rule).
5. **Backward-compat at API boundaries.** New fields/columns are optional. Missing migration must not crash the app (project rule in `CLAUDE.md`).
6. **Semantic audit before Phase gate.** Before closing a phase, grep for any forbidden-duplicate patterns the phase was supposed to eliminate (memory rule). **Phase 1 specific pre-gate greps (must return zero hits):**
   - `grep -rn "prewarmTranscription" Sources/` — the removed eager prewarm path must not survive anywhere.
   - `grep -rn "downloadProgress\b" Sources/SeshatAppKit/MenuBar/` — the renamed identifier in `MenuBarSceneModel` (now `preparationProgress`) must not survive.
   - `grep -rn "ParakeetArtifact" Sources/` — after Step 1.7, the enum must be gone.
   - `grep -rn "Color(hex:" Sources/SeshatAppKit/` outside of `Theme/SeshatTheme.swift` — only a pre-Phase-2 check; ok to leave a stub that fails loudly once Phase 2 begins.
7. **Commit subject format:** `phase-N step N.M: <verb-led description>`. No emojis.
8. **Test parallelism off for suites that touch `testingBaseDirectoryOverride`.** Concretely: add a static `NSLock` in `SeshatConfigTests` / any other test class that mutates the override, wrap `setUp()` / `tearDown()` state-touch code in `lock.lock() / lock.unlock()`. Do not rely on `-parallel-testing-enabled NO` at the command line — that flag does not propagate through `swift test` consistently and future maintainers will re-enable parallelism without realising.

---

## Phase 1 execution sequencing (dependency DAG)

```
          ┌─────── 1.1 Task.detached ────┐
          ├─────── 1.2 log catch ────────┤
          ├─ 1.1  Task.detached         — DONE in 1cb665c
          ├─ 1.1b signposts              — pending
          ├─ 1.2  log catch              — DONE in 1cb665c
          ├─ 1.3a menu bar click verify  — pending
          ├─ 1.3b menu bar regression    — pending
          ├─ 1.4  pill click tests A/B   — DONE in 1cb665c
          └─ 1.4b drag-suppresses-tap    — pending
          │
          ├─ 1.5 ModelRegistry ────┐
          │                         ├─ 1.7 Transcriber refactor ── 1.8 smoke test
          ├─ 1.6 SeshatConfig ─────┘
          │
          ├─ 1.9 IM permission (backend only)
          │
          ├─ 1.11 TranscriptStore (JSONL + ring)
          │     └─ 1.12 plumb through ── 1.13 build info caption
          │
          └─ 1.14 backlog recon ── 1.15 DMG + dogfood  ← Phase 1 gate
```

**Parallel safe:** 1.1b / 1.3a / 1.3b / 1.4b can run in any order independently (disjoint files). 1.5 + 1.6 parallel, then 1.7 sequential. 1.9 parallel with 1.5/1.6. 1.11 parallel with 1.5/1.6/1.9, then 1.12 → 1.13 sequential. 1.14 and 1.15 serialise at the end.

---

## Open questions (resolve before Phase 2 kickoff)

1. Do we want snapshot testing for UI components in Phase 2, or stick to manual `#Preview` verification? (cost: +1 dependency; benefit: regression safety on visual tweaks)
2. Does `SeshatAppKit` as an executable SPM target need an asset catalog wrapper, or can we embed PNGs directly? (check `.process("Resources")` behaviour with .app bundle packaging)
3. Light mode: build alongside dark in Phase 2, or ship dark only and do light in 2.F follow-up? (affects 2.D scope)
4. `WaveformView`'s draw frequency — 60 Hz `TimelineView` vs. on-demand? (CPU cost for always-on pill)
5. Signing / notarization path beyond ad-hoc? (separate operational task; blocks wider distribution but not dogfood)
