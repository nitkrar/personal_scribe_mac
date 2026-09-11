# Phase 2 — Friction-pattern evidence (raw inputs to the 7-day analysis)

**Date:** 2026-04-25
**Companion summary:** `2026-04-25-agent-execution-retrospective.md` Part 2

This file persists the primary sources behind the six recurring failure patterns
and three "3× time" instances in the summary file.

Companion artifacts:
- **Full 7-day commit log with file-change stats:** `2026-04-25-phase-2-git-log-7d.txt` (1,978 lines, alongside this file)
- **Six investigation files** referenced below all live in this same directory under their original `2026-04-{22,23,24}-*.md` names

---

## 1. 7-day commit summary (Apr 18 → Apr 25)

Total ~120 commits across the window. Full output with `--shortstat` lives at
`./2026-04-25-phase-2-git-log-7d.txt`. The headline subjects below are sufficient
for the friction-pattern analysis:

```
2026-04-25
  e8cb597  phase-3 step #024.7: prewarm new model on setActive + tab-switch refresh
  0c55b16  phase-3 step #024.6: expand catalog with FluidAudio's other ASR + diarization variants
  376f2ed  phase-3 step #024.5: align disk layout to FluidAudio's source of truth

2026-04-24
  64c89bf  #068 step 1 close: BACKLOG entry — Stage A done, Stage B pending
  bf28dd3  #068 step 1: menu-bar Mode submenu
  d7da8f9  phase-3 step #024.4: wire Retry to download, tighten setActive test
  98cf401  phase-3 step #024.3: separate activate from download
  829b776  phase-3 step #024.2: DefaultModelService.removeDownloaded + ModelRow delete/activate redesign
  73c0ba9  phase-3 step #024.1: ModelBoundTranscriberProvider.removeDownloadedFiles
  e3410da  #076 close: mute system audio while recording shipped in 89ab9de
  d3b2904  #075: mark done — changelog + root-cause summary
  89ab9de  mute system audio while recording toggle                                                  [11 files / +441 / −11]
  82eade2  #075 step 1.7: drop the too-short chip; pill goes straight to idle
  c8ac42d  #075 step 1.6: manual verification runbook MV-SHORT-1..6
  6ebbc31  #075 step 1.5: delete PersonalScribeError.recordingTooShort
  13b6b0f  #075 step 1.4: assert card renders nothing for .shortExit
  6d89cd5  #075 step 1.3: pill renders short-exit chip for 1.5s via AppStore
  c89a6d8  #075 step 1.2: orchestrator publishes .shortExit instead of .error(.recordingTooShort)
  597055e  #075 step 1.1: SessionState.shortExit case + displayState mapping
  9d01f84  #017 stage A: live-apply hotkey customization + plist collision + restore-default        [11 files / +723 / −33]
  8d06afc  #072: consolidate clipboard snapshot + orthogonal auto-paste/restore toggles              [28 files / +2868 / −829]
  b682a26  #046 post-ship: version-agnostic VAD bundle + direct MLModel load
  10bcc6a  #073: Launch at Login info icon is now a clickable deep-link to System Settings
  6c6505f  settings: Background mode replaces Show in Dock; shared relaunch-required pattern
  5519113  #046 stage b tuning + runbook reorg: 3s grace, 1-10s slider, notification sticks, Manual*Verification → Tests/ManualVerifications/
  ef023e4  #046 stage b chunk e: composition link-wiring + bundle-model safety + runbook
  a126b17  #046 stage b chunk d: settings auto-stop collapsed section + warn/notify toggles
  017d933  #046 stage b chunk c: response-card driver + view link support
  c689560  #046 stage b phase 1+2: grace-window core types + orchestrator state machine
  99cee6a  cleanup: prune dead tests in PersonalScribeCoreTests                                     [12 files / −286]
  a372e34  cleanup: prune dead tests in PersonalScribeAppKitTests                                   [12 files / −189]
  78c3ba3  cleanup: prune dead + redundant tests across audio / transcription / session             [21 files / −885]
  15e2496  #046: VAD auto-stop Stage A — bundled Silero + detached-Task stop + Settings card        [20 files / +2015 / −11]

2026-04-23
  00d836a  trunk: collapse session state through single pipeline snapshot stream                    [22 files / +323 / −365]
  d3696ed  trunk: bump pill sine-wave amplitude + drop tautological size tests
  9302f8f  cleanup: exclude Manual*Verification.md runbooks from SPM + gitignore py bytecode
  d7f8f49  trunk: pill dimension bands — Height/Width enums prevent drift

2026-04-22
  9415e15  cleanup: silence Swift 6 source-side warnings + port package script to Python
  ed1f612  #013 step 1.3: add transcript row editing sheet
  aef1a74  #013 step 1.2: reload transcript edits in the tab
  8affe56  #013 step 1.1: persist transcript row edits
  db791b0  #016 step 1.3: simplify policy + tests — drop premature abstraction                      [3 files / +22 / −171]
  da96525  #016 step 1.2: DefaultModelService consults RAM policy on first launch
  930330e  #016 step 1.1: DefaultModelSelectionPolicy for RAM-aware default                         [2 files / +196]
  15c2f2e  #015 step 1.1: observer flips OnboardingCompleted on required-perms grant                [6 files / +437]
  b3f3278  bug-007 step 1.4: AIModelsTab row shows description + ⓘ popover
  33d25a1  bug-007 step 1.3: ModelInfoPopoverPresenter with computed-relative ranks
  0df02cd  bug-007 step 1.2: pivot ModelDescriptor to published benchmarks                          [8 files / +127 / −72]
  68ece00  #011 step 1.3: add transcriptions row delete affordance
  30b13f3  #011 step 1.2: reload transcriptions after delete
  bd5ceff  #011 step 1.1: persist transcript row deletion
  457ca81  bug-007 step 1.1: ModelDescriptor gains shortDescription + RelativeRating                [8 files / +140 / −5]
  0e1f284  bug-039 step 1.2: AIModelsTab onAppear refresh + MV-SETT-STALE runbook
  48423e0  bug-039 step 1.1: DefaultModelService.refresh() re-syncs states to disk
  9d1dfb1  trunk: #042 — AX probe gate swaps to PID inequality                                      [9 files / +707 / −134]
  90af8c6  bug-002 step 2.4: MV-PUX runbook updated for Esc true-discard
  5e1f7fe  bug-002 step 2.3: Esc handler wired to cancelIfActive (true-discard)
  d2c57b7  bug-002 step 2.2: coordinator cancelIfActive (true-discard)
  1c2f37f  bug-002 step 2.1: pipeline cancelCapture (true-discard)
  a786db1  bug-071 step 1.5: MV-HOLD runbook + investigation artifacts
  e55d8f7  bug-071 step 1.4: rewire hold hotkey to coordinator hold API + delete sticky-hold guard  [5 files / +25 / −58]
  0facbba  bug-071 step 1.3: coordinator gains startHoldIfIdle + stopIfActive (Option A)
  b545753  bug-071 step 1.2: pipeline startHoldCapture publishes .holdRecording eagerly
  26122a6  bug-071 step 1.1: add SessionState.holdRecording + pill mapping

2026-04-21 (selection — full list in the .txt)
  de7e4ae  trunk: #008 followup — test init compat with new inputDeviceProvider param
  4cf5a9b  trunk: #008 — sidebar mic footer shows current input device name                          [6 files / +407]
  a97e575  trunk: #006 — compact base-directory row + Finder opens folder itself
  3a15cb3  trunk: #041 — unified window follows active space instead of pinning
  91ea8fa  #043 followup: mark DatabaseOperationStatusTests @MainActor
  a5a841a  #043: DatabaseOperationStatus observable plumbing                                        [4 files / +308]
  45ed17f  trunk: #040 + #044 followup — dark-shell helpers + pill test spy compat
  2048b66  trunk: #005 — Launch-at-Login status feedback
  5e560a4  trunk: #044 pill panel resize per state — kill the click-halo                            [6 files / +475 / −16]
  ab0ed95  storage-layer step 3.1: delete shim + SQLiteMetricsReader + legacy readers               [10 files / +92 / −742]
  cbcfaf3  storage-layer step 2.4: wire AppComposition + NotesWindow to shared AppDatabase
  69ed74f  storage-layer step 2.2: rewire metrics readers to AppDatabase + delete MetricsSnapshotStore.init(databaseURL:)
  1d6446d  storage-layer step 2.1: swap SessionCoordinator + pipeline to TranscriptRepository
  3b1aaf5  storage-layer step 2.3: collapse SQLiteTranscriptStore to shim + nuke TranscriptStoreJSONL [4 files / +21 / −987]
  903ffd0  storage-layer step 1.4: introduce TranscriptRepository CRUD surface
  6f06488  storage-layer step 1.3: add GRDB conformance to TranscriptEntry
  db4ccde  storage-layer step 1.2: scaffold AppDatabase + migrator + error envelope
  5145cf7  storage-layer step 1.1: pin transcripts.sqlite DDL + absorb Phase 3.D
  ca95584  trunk: backlog migration — consolidate plans/backlog + PLAN_PHASES into BACKLOG.md + ROADMAP.md
  608e7fb  trunk: backlog — fix ui-mockup-gaps.md SHA citations
  a67a2c8  trunk: backlog — sanity-check pass; mark #1 + #5 with current FIXED status
  47a25d2  trunk: housekeeping — move agents_status.py to scripts/; ignore WIP plans/ paths
  a77724b  trunk: bugs #6 + #16 — compact menu-bar header + History/Settings entries
  0b70f1d  trunk: mockup-gaps G.3 test fix — drop WindowTint.dark assertion in TranscriptionsTabTests
  37f9384  trunk: mockup-gaps G — backlog check-offs + resolution paragraph
  35adcd8  trunk: mockup-gaps G.4 — Theme picker + conditional tint visibility
  76969af  trunk: mockup-gaps G.3 — reroute former WindowTint.dark call sites
  f04ad4c  trunk: mockup-gaps G.2 — drop WindowTint.dark case
  8e45f33  trunk: mockup-gaps G.1 — AppTheme enum (Light/Dark/System, default Light)
  a21e7b6  trunk: bug #14 — demote Shortcuts from standalone sub-tab to General subsection
  8b829a3  trunk: CLAUDE.md — SeshatTheme is informational + theme types live in AppKit/Theme
  6af1eaf  trunk: mockup-gaps F — backlog check-offs with trunk SHAs
  fca6e6f  trunk: mockup-gaps F.5 — merge Typography.display into Typography.title
  bcab59b  trunk: mockup-gaps F.4 — doc-comment the palette-vs-Status split
  b8f0068  trunk: mockup-gaps F.3 — drop dead Accent enum
  c23c9d9  trunk: mockup-gaps F.2 — drop dead Palette.pillStopRed
```

### Aggregate stats over the 7-day window

- **~120 commits**, ~85 of which use `step N.M:` micro-commit cadence
- **3 bulk-test-cleanup commits on Apr 23-24 night** totaling 1,360 deletions:
  - `78c3ba3` — 21 files / −885 (audio/transcription/session)
  - `a372e34` — 12 files / −189 (PersonalScribeAppKitTests)
  - `99cee6a` — 12 files / −286 (PersonalScribeCoreTests)
- **Massive refactor commits** (>1,000 line changes):
  - `8d06afc` (#072 snapshot unification) — 28 files / +2868 / −829
  - `15e2496` (#046 Stage A VAD) — 20 files / +2015 / −11
  - `9415e15` (Swift 6 warnings + Python package script) — 8 files / +567 / −389
  - `00d836a` (pill flicker — collapse pipeline snapshot) — 22 files / +323 / −365
- **Speculative-abstraction round-trips**:
  - `930330e` (+196) → `db791b0` (+22 / −171) on #016 — net deletion of speculative abstraction
  - `457ca81` (+140 / −5) → `0df02cd` (+127 / −72) on bug-007 — architecture pivot
- **Investigation-heavy days**: Apr 22 (~18 commits), Apr 24 (~24 commits), Apr 23 night was test-cleanup.

---

## 2. Investigation files referenced

All of these live alongside this file in `plans/investigations/`. The summary
analysis quotes from them; this section indexes them with key excerpts so the
chain of evidence is intact even without re-reading the full files.

### `2026-04-22-042-ax-probe-claude-2.md` (10.4 KB) — second-pass independent review

```
ROOT CAUSE confirmation:
"The probe at ClipboardBatchOutput.swift:220-259 queries kAXFocusedUIElementAttribute
on the system-wide element, then returns true only if the focused element exposes
kAXInsertionPointLineNumberAttribute, kAXSelectedTextAttribute, or has role in
{kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole}. Sublime Text draws its
editor buffer in a custom NSView (no NSTextView inheritance), so its focused
element typically reports role AXGroup or AXUnknown and exposes neither
insertion-point nor selected-text as readable attributes. attributeIsReadable
requires status == .success && value != nil — both fail for non-text surfaces.
Probe returns false, deliverBatch hits the guard at :113-116, returns
.clipboardOnly..."

OPTIONS WEIGHED: 5 separate options compared (PID inequality, extended roles,
revert to bundle-ID, hybrid bundle-ID + PID rescue, AXSetAttributeValue).
Recommended: Option 1 (PID inequality) for honesty + minimal LOC delta.

Companion files (all 4 from #042): ax-probe-claude.md, ax-probe-claude-2.md,
ax-probe-codex-prompt.md, ax-probe-codex.md.
```

### `2026-04-23-pill-flicker-root-cause-codex.md` (8.2 KB)

```
ROOT CAUSE: ordering race in SessionCoordinator (NOT pipeline, NOT overlay).

"SessionPipelineOrchestrator.stopRecordingAndRunPipeline() republishes
sessionState = .transcribing at every stop-path stage transition... The
orchestrator exposes those snapshots both as a latest-value pull (snapshot())
and as a stream that yields every publish... SessionCoordinator consumes the
same pipeline state through two unsynchronized paths: direct post-call refresh
and background stream observer... Because there is no freshness token, the
direct refresh can apply the newest terminal .idle first, while the observer
path still has an older buffered .transcribing snapshot to deliver later. When
that stale .transcribing finally arrives, currentState is already .idle, so the
coordinator republishes .transcribing, and then later republishes .idle again."

VISIBLE SEQUENCE: .transcribing → .done → .transcribing → .done

FIX: monotonic snapshot revision in PipelineSnapshot.

CONFIDENCE: high. Independently confirmed by Claude flow audit
(2026-04-23-pipeline-flow-audit-codex.md, 18.8 KB).
```

### `2026-04-24-issue-075-hold-too-short-wedge-claude.md` (17.8 KB) — wedge investigation

```
TL;DR: "Symptom 1 (overlap) and Symptom 2 (hold wedge) share a root cause:
when .error(.recordingTooShort) is published, the UI layers and the
coordinator's startHoldIfIdle guard all disagree about when that state should
end. There is no single clearing moment — the pill glyph clears after 1.5s,
the ResponseCard does not clear at all, and the coordinator only clears on
toggle() / cancelIfActive()."

OPTIONS: A (let startHoldIfIdle accept .error), B (clearErrorIfAny step), C
(auto-clear .error after delay), D (split ResponseCard error-content lifecycle),
D' (drop error from ResponseCard driver entirely).

RECOMMENDATION: Option A + Option D'.

Companion files: issue-075-claude-review-prompt.md, issue-075-claude-review-codex.md,
issue-075-fix-options-codex.md, issue-075-wedge-trace-codex.md.

Final ship was not Option A — was the user-driven .shortExit reframe (it's not
an error). See BACKLOG #075 changelog (excerpted below).
```

### `2026-04-24-mute-system-audio-codex.md` (3.5 KB) — initial codex review

```
VERDICT: ship-with-changes

MUST-FIX (4 items):
- SystemOutputMuter cannot latch only priorState: Bool? — must remember
  device(s) it muted (route-change semantics)
- Capture-stream error path doesn't guarantee wrapper cleanup
- Clean quit not covered (NSApplication.shared.terminate doesn't route through
  coordinator.stopIfActive())
- kAudioHardwarePropertyDefaultOutputDevice ≠ system audio (alerts route
  through kAudioHardwarePropertyDefaultSystemOutputDevice)

ALTERNATIVES CONSIDERED:
"I do not see a materially simpler supported macOS API than HAL property writes.
The simplification worth taking is contractual, not technical..."

→ User pushed back: "how complicated is muting audio on a laptop"
→ Two more rounds of "simpler" prompts (mute-system-audio-simpler-codex.md
   and mute-system-audio-simpler-codex-2.md) ensued
→ Even simpler-codex-2 said "I would not make AppleScript the default
   implementation. My preferred v1 is still small, but native"
→ User shipped AppleScript anyway — 20 lines.
```

### `2026-04-24-mute-system-audio-simpler-codex-2.md` (2.8 KB) — second simpler pass

```
"What I would keep from the simpler pass:
- Keep the mute latch inside AVAudioCaptureService...
- Keep quit handling cheap...
- Keep the test surface narrow...

What I would change:
- I would not make AppleScript / NSAppleScript the default implementation.
- My preferred v1 is still small, but native: add a tiny SystemOutputMuter in
  PersonalScribeAudio and inject it into AVAudioCaptureService.
..."

Final shipped: AppleScript (89ab9de). Memory file project_macos_system_audio_mute.md
codified the conclusion:
  "set volume output muted via NSAppleScript is route-independent, covers all
   output routes, ~20 LoC. CoreAudio HAL kAudioDevicePropertyMute is per-device
   and over-engineering for 'mute the laptop.'"
```

### `2026-04-24-snapshot-unification-claude.md` (21 KB, partial — first 100 lines read)

```
Step 1 audit confirms the brief's two-system summary:

System A — PasteboardSnapshotService (session-lifecycle)
- Plain string only
- Single optional slot (overwrites on second snapshot)
- PasteboardSnapshotHost in PersonalScribeAppMain.swift owns it

System B — ClipboardBatchOutput inline snapshot (output-pipeline)
- Full [NSPasteboardItem] round-trip (RTF, file URLs, multi-type items)
- Transient stack-local — no instance field
- Schedule-restored unconditionally after delay

What the brief didn't flag:
- Neither system captures changeCount
- The two systems snapshot at different moments
- Test seams diverge
- Anti-pattern already logged: BACKLOG #074 calls this out under the state-
  ownership audit

Proposed unified API:
- Keyed multi-slot via opaque SnapshotToken
- snapshot() / restore(token:) / restoreIfUnchanged(token:) / discard(token:)
- Service does not observe AppStore, sessions, or paste delivery — pure seam
  over NSPasteboard

Ship landed as 8d06afc (28 files / +2868 / −829).
```

---

## 3. BACKLOG ticket bodies (key tickets)

### `#016 — RAM-aware default model selection` (the 3X-time speculative-abstraction case)

```markdown
**Reframed 2026-04-22:** original ticket title was "Second model descriptor
(parakeet-tdt-110m)" — stated intent was "for lower-RAM devices," but the
registered catalog ID was a naming guess that doesn't match what NVIDIA
publishes. The lightweight variant NVIDIA ships is `parakeet-tdt-ctc-110m`
(Hybrid FastConformer-TDT-CTC, 110M params, 407 MB), already registered in
`BuiltInModelCatalog` via Layer 6 work. So "the second model exists" is already
satisfied — what's missing is the *RAM-aware default selection* the original
ticket's motivation actually described.

**Scope (current):** on first launch (no persisted `ActiveModelDescriptor` in
UserDefaults), inspect `ProcessInfo.processInfo.physicalMemory`. If below a
threshold (≤ ~10 GiB, i.e. 8 GB Macs), default to the lightest registered model
(`parakeet-tdt-ctc-110m`). Otherwise default to `parakeet-tdt-0.6b-v2`
(unchanged). User choice always wins — once persisted, the RAM probe is never
consulted again.

**Changelog**
- 2026-04-22 `930330e` step 1.1 — `DefaultModelSelectionPolicy` — first attempt,
  over-engineered: generic "pick lightest registered model with declared
  parameterCount, tiebreak on size, fall back to baseline if no lighter
  candidate." 8 tests covering the defensive branches. Walked back in step 1.3.
- 2026-04-22 `da96525` step 1.2 — `DefaultModelService` convenience init gains
  `physicalMemoryBytes: Int64 = Int64(ProcessInfo.processInfo.physicalMemory)`,
  feeds into the policy, uses the result as `Preference<ActiveModelDescriptor>.default:`.
- 2026-04-22 `db791b0` step 1.3 — simplify policy + tests. Collapsed step-1.1's
  generic registry-scanning logic to a three-line
  `physicalMemoryBytes < threshold ? lightweight : baseline`; caller names the
  two candidates at the call site. 8 policy tests → 2. Rationale: defensive
  filtering was speculative complexity for catalog shapes that don't exist
  today; per global CLAUDE.md, three similar lines beat a premature abstraction.
```

### `#007 / bug-007 — Model labels are opaque` (the 3X-time architecture-pivot case)

```markdown
**Scope shape locked 2026-04-22:** BOTH inline description AND a popover (not
either-or). ⓘ icon next to display name; popover top shows Speed + Accuracy
(relative-bar + label) + Size (actual bytes); then Architecture / Repository /
Revision / Parameters. Ratings are computed-relative — ranks derived at render
time from `ModelPerformance` benchmarks on each descriptor, no hardcoded
label-per-model map.

**Changelog**
- 2026-04-22 `457ca81` step 1.1 — initial schema (walked back in 1.2):
  ModelDescriptor.shortDescription + RelativeRating enum + speedRating /
  accuracyRating fields. Enum-based approach put user-facing labels in code
  rather than the registry — user called it out.
- 2026-04-22 `0df02cd` step 1.2 — pivot to published benchmarks. Remove
  RelativeRating + rating fields + TranscriptionEngine.displayName. Add
  architecture: String (required), performance: ModelPerformance (optional
  averageWER, rtfx, parameterCount). Catalog populated from HuggingFace Open
  ASR leaderboard (v2: 6.05% WER, 3386 RTFx; CTC: 7.49%, 5345; v3: 6.34%, 3333).
  Label vocabulary falls out of rank, not hardcoded.
- 2026-04-22 `33d25a1` step 1.3 — ModelInfoPopoverPresenter computes relative
  rank within siblings, maps to 3 tiers via (rank * 3) / N. 19 tests.
- 2026-04-22 `b3f3278` step 1.4 — AIModelsTab row shows inline shortDescription
  + ⓘ info button.
```

### `#072 — Paste to cursorless surface silently drops clipboard` (the parallel-systems case)

```markdown
**Landed (2026-04-24, 8d06afc):** Fix direction D — opt-in restore.
- New ClipboardRestoreEnabled pref defaults to false → transcript stays on
  clipboard indefinitely, structurally preventing the silent-drop symptom.
- Paired with restoreSnapshotIfUnchanged(_:token:) changeCount guard (for
  users who opt restore ON) so the delayed restore skips if anything has
  written to the clipboard since our transcript landed.
- Auto-paste toggle (replacing PasteMode picker + unwired
  PasteEnabledPreference) defaults to true.
- Slider default bumped 0.5s→3.0s, max 5.0s→10.0s.
- PasteboardSnapshotService + ClipboardBatchOutput.savedItems unified into one
  service (pre-empts the #074 anti-pattern example).

Stats: 28 files / +2868 / −829.
```

### `#075 — Hold-to-record + too-short recording wedges hold path` (the investigation>impl case)

```markdown
**Root cause (user-identified):** "Recording too short" was misclassified as
an error. It's a normal pipeline shortcut (nothing to transcribe), not a
failure. The wedge was emergent from .error being a sticky state with
inconsistent recovery paths per entry point; the double-render was from two
surfaces (pill + card) both observing .error(.recordingTooShort).

**Fix direction:** reclassify. New SessionState.shortExit non-error terminal
case, display-maps to .idle so every entry-point guard accepts it as startable.
PersonalScribeError.recordingTooShort deleted. Pill flips straight to idle (no
chip, no message); card renders nothing for .shortExit.

**Changelog (7 micro-commits, 2026-04-24)**
- 597055e step 1.1 — SessionState.shortExit case + displayState mapping
- c89a6d8 step 1.2 — Orchestrator publishes .shortExit instead of .error
- 6d89cd5 step 1.3 — Initial: AppStore emits .error(message:) chip for 1.5s
  (superseded by 1.7)
- 13b6b0f step 1.4 — Card-driver regression test
- 6ebbc31 step 1.5 — Deleted PersonalScribeError.recordingTooShort
- c8ac42d step 1.6 — Manual verification MV-SHORT-1..6
- 82eade2 step 1.7 — Dropped the too-short chip entirely. User feedback:
  reusing .error(message:) kept the misclassified framing in the UI layer and
  hit a pre-existing SwiftUI rendering quirk where error text persists past
  panel resize.

Investigation cost: ~35 KB across 4 files (claude-review-prompt + claude-review-
codex + fix-options-codex + hold-too-short-wedge-claude).
Implementation cost: 7 small commits.
```

### `#071 — Hold-to-record stuck after release` (architecture-heuristic case)

```markdown
**Root cause (consensus from 4 independent agent investigations 2026-04-22 —
2× Claude + 2× Codex):**

Async race between hold-start and hold-release Tasks. startIfIdle() calls
pipeline.toggleCapture() which runs capture.start() *before* publishing
.recording. If the user's release lands during that window, stopIfRecording()
reads currentState == .idle and silently no-ops. The start task then completes,
publishes .recording, and the session is stuck recording forever.

**Fix direction (recommended — not locked):** .holdRecording as a first-class
SessionState case. Hotkey layer calls coordinator.startHold() / stopHold().
Store's derivePillVisibility emits .holdToRecord from .holdRecording — same
channel as .recording. Kills the start/stop race (transitions now have a known
source state), removes the side-channel pill push, gives store a single
authoritative view of hold-ness.

**Changelog (5 micro-commits, 2026-04-22)**
- 26122a6 step 1.1 — SessionState.holdRecording case + pill mapping
- b545753 step 1.2 — pipeline startHoldCapture publishes .holdRecording
  EAGERLY before awaiting capture.start() — core race fix
- 0facbba step 1.3 — Coordinator Option A API (startHoldIfIdle / stopIfActive)
- e55d8f7 step 1.4 — Composition rewire + delete sticky-hold guard +
  delete onHoldStartVisibilityPush side-channel
- a786db1 step 1.5 — MV-HOLD runbook
```

---

## 4. Connection to memory feedback files

The friction patterns visible in the commit log have direct memory-file analogues:

| Pattern (commit-visible) | Memory file containing the rule |
|--------------------------|--------------------------------|
| Speculative abstraction round-trip (#016 1.1→1.3 wipe) | `simplicity_discipline.md` §4 |
| Architecture pivot at 1.2 (bug-007) | `architecture_heuristics.md` §2 (per-caller patterns are contract questions) |
| #072 parallel systems | `architecture_heuristics.md` §1 + BACKLOG #074 |
| #071 race fix at pipeline layer | `architecture_heuristics.md` §1 verbatim — "race fixes belong in pipeline not coordinator" |
| 1,360-line dead-test prune | `test_review_heuristics.md` (dead-test taxonomy) + `feedback_tests_as_spec.md` (bug fossils) |
| #075 over-classified-as-error reframe | `feedback_user_intent_over_literal_read.md` (read user-named gaps as intent) |
| #076 mute audio over-engineering | `project_macos_system_audio_mute.md` (HAL is over-engineering, AppleScript is right) |
| #042 needing 3 independent reviews | `proposal_discipline.md` §4 (codex reviewers are rigorous — trust their critical findings) |

Many of these memory files were *consolidated* in the 2026-04-23 session
(`f5605899`) — i.e. authored as a response to the very patterns that produced
them. The execution loop now has both the friction (in commits) and the codified
remedy (in memory), but the rules don't always fire on time during agent
execution. See Phase 3 for the per-session pushback rates.

---

## 5. The three "3× time" instances — full evidence

### 3X-1: `#016` RAM-aware default model

**Net commit pattern**
```
930330e  +196        DefaultModelSelectionPolicy (over-engineered)
da96525  +108        wire it into DefaultModelService
db791b0  +22 / −171  simplify policy + tests — drop premature abstraction
```

**Net useful work**: a 3-line `physicalMemoryBytes < threshold ? lightweight : baseline` plus a wiring change. Three commits to land what's a sub-1-day junior engineer task. The first commit's 8 tests + generic registry-scanning logic was pure speculation — codified in BACKLOG #016 changelog as the explicit rationale for the walk-back.

**User quote at the time** (`c765cbed turn=24`):
> "I thought this would be a simple test file of mocking memory and checking if it picked well. i don't understand are we adding so many tests for. is there something i don't know that we should be testing here?"

### 3X-2: `bug-007` model labels architecture pivot

**Net commit pattern**
```
457ca81  +140 / −5    schema 1: RelativeRating enum + ratings on descriptor
0df02cd  +127 / −72   schema 2: published benchmarks on descriptor + delete schema 1
33d25a1  +400         presenter that computes ranks at render time
b3f3278  +233 / −36   AIModelsTab row + popover wiring
```

**Pivot moment**: BACKLOG #007 changelog cites this verbatim:
> "Enum-based approach put user-facing labels in code rather than the registry — user called it out."

**User quotes triggering the pivot** (`c765cbed turn=8 + turn=9`):
> "why are we implementing labels as descriptors? don't we have a model registry which should have all the info"
> "why are we implementing labels in code? don't we have a model registry which should have all the info"

### 3X-3: `#075` wedge — investigation > implementation

**Investigation files (2026-04-24, all in this dir)**
```
19:16  issue-075-hold-too-short-wedge-claude.md         17.8 KB
19:34  issue-075-wedge-trace-codex.md                   3.9 KB
19:39  issue-075-fix-options-codex.md                   5.5 KB
19:40  issue-075-claude-review-prompt.md                3.7 KB
19:50  issue-075-claude-review-codex.md                 8.9 KB
                                                       -------
                                                       ~40 KB total, ~35 min
```

**Implementation commits (same day, 20:24 → 21:05)**
```
597055e  step 1.1   SessionState.shortExit case + displayState mapping
c89a6d8  step 1.2   orchestrator publishes .shortExit instead of .error
6d89cd5  step 1.3   pill renders short-exit chip for 1.5s via AppStore
13b6b0f  step 1.4   assert card renders nothing for .shortExit
6ebbc31  step 1.5   delete PersonalScribeError.recordingTooShort
c8ac42d  step 1.6   manual verification runbook MV-SHORT-1..6
82eade2  step 1.7   drop the too-short chip; pill goes straight to idle
```

**Each commit is small** (tens of lines). Investigation took as long as implementation because two coupled symptoms (pill + card overlap, hold path wedge) had to be traced to a shared root cause (.error(.recordingTooShort) had no single clearing moment) before fix options could be evaluated.

The 17.8 KB `claude.md` investigation maps the entire state machine, four fix options with trade-offs, and recommends Option A + Option D'. The eventual ship was a *user*-driven reframe (it's not an error in the first place), which neither agent proposed.

---

## End of Phase 2 evidence file
