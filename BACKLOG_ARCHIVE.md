# Ninimma — Backlog Archive

Closed items. Source of truth for "what was the fix for that thing I filed months ago?". Active items live in [`BACKLOG.md`](./BACKLOG.md).

**Note on granularity:** items below are archived by source group rather than one-ticket-per-closed-item. Fine-grained per-item status lives in the original source doc (moved to `plans/_legacy/`, since deleted) or in git history via the cited commit SHAs.

**Deleted plan docs:** `plans/_legacy/`, `plans/central/` (and its prompt/phase/sequencing docs), most of `plans/investigations/`, the April review docs (`REVIEW*.md`, `CODEX_ML_REVIEW.md`, `ASSISTANT_FEASIBILITY_REVIEW.md`), `explorations/`, `plans/013_notes_window/_archived_overengineered_v1/`, the per-ticket plan folders (`plans/046_*` through `plans/101_*`, `plans/streaming_whisper/`) and `plans/seshat_stt_eval-*.md` were removed once their tickets closed. Read them with `git show 8755ff7:<path>`.

---

## From `ui-mockup-gaps.md` (22 closed)

| Group | Items | Commits |
|---|---|---|
| Home B | B.1 empty state · B.2 "RECENT TRANSCRIPTIONS" label · B.3 "Mins saved" · B.4 WPM integer at zero | `1d4fcef`, `b05609e`, `d3639b4`, `776aa7c` |
| Transcriptions A | A.1 title/preview dedup · A.2 compact date format · A.3 row height · A.4 wall-clock timestamps · A.5 WindowTint on tab root | `050d46b`, `7f42970`, `5d75d40`, `0bb8084`+`e9c9481`, `7d460cf` |
| Permissions C | C.1 section header · C.2 rounded row cards · C.3 filled Grant Access pill · C.4 "Required" label · C.5 "Granted" label · C.6 mic subtitle copy · C.7 Input Monitoring subtitle from `HotkeyPreference` | `2bbf57b`, `529d399`, `6ddd612`, `e6fc482`, `69566d1`, `24cc9f8`, `d5b6379` |
| Settings→General D | D.1 Style picker + live pill previews · D.2 APPLICATION section + "Show in Dock" · D.3 TEXT INPUT section + paste toggle | `ee4d7ca`, `6108a19`, `41c3f6c` |
| Theme tokens F | F.1 drop `Radius.pill` · F.2 drop `Palette.pillStopRed` · F.3 drop `Accent` enum · F.4 palette-vs-`Status.*` comments · F.5 merge `Typography.display` → `Typography.title` | `afd925d`, `c23c9d9`, `b8f0068`, `bcab59b`, `fca6e6f` |
| Palette bundle G | G.1 introduce `AppTheme` · G.2 drop `WindowTint.dark` · G.3 `Palette.for(scheme:)` authoritative · G.4 Settings picker + conditional tint visibility | `8e45f33`, `f04ad4c`, `76969af`, `35adcd8` |

Plus: startup lifecycle (`startupCoordinator.start()` wired — `e3eec52`) · Modes live refresh (Set Active + `activeModeStream` — `09d7612`) · app bundle size regression (release-only `strip -x` — `561e157`).

---

## From `ui-dogfood-bugs-2026-04-21.md` (9 closed)

| Legacy ID | Title | Commits / note |
|---|---|---|
| #1 | About tab traps navigation (1a/1b/1c) | `726e538` · `1196e73` · `cd776df` |
| #2 | Hide "Check for Updates" from menu bar | removed stub entirely |
| #4 | Global hotkey dies when app frontmost | `a12b7e2` + `f3773e6` — local monitor alongside global, swallow with `hotkeyKeyDownSwallowed` flag |
| #6 | Menu-bar brand wraps to 2 lines | merged brand + mode into one em-dash header |
| #8 | "Settings" largeTitle redundancy | removed above the sub-tab picker |
| #9 | "Copy Last Transcript" no-op | wired to strict clipboard-only `CopyLastTranscriptAction` |
| #14 | "Shortcuts" tab demoted | moved into General subsection; standalone tab/enum deleted (`a21e7b6`) |
| #16 | "Settings" + "History" menu-bar entries | added via `showWindow(selecting:)` pattern from #1a |

---

## From `PLAN_PHASES.md` Phase 1 (closed steps)

All Phase 1 steps merged via `1cb665c` and follow-ups. Surviving leftovers tracked as active:
- **#010** — drag-suppresses-tap end-to-end test (Step 1.4b)
- **#012** — OSSignposter instrumentation (Step 1.1b)

Everything else (1.1, 1.2, 1.3, 1.5, 1.6, 1.7, 1.9, 1.11, 1.12, 1.13, 1.14, 1.15) landed on trunk. Phase 1 gate met.

---

## From `PLAN_PHASES.md` Phase 2 (done)

Sprint 1 (Theme + foundations + components) and Sprint 2 (pill rewrite + composite components) fully landed. Native `NSMenu` menu bar landed. Custom `.icns` in DMG. Dark/light mode wired. M-series (M1–M5) covers the post-Phase-2 menu-bar + unified-window polish — see `project_seshat_execution_state` memory and commit range ending at `ce02bf1`.

---

## From `plans/central/` (Stage 3 executed)

Per `plans/central/INDEX.md` (2026-04-20): 7 approved-now delete rows landed on trunk. L2, L3, L6, L7, L9 Stage 2 fully landed. `swift build --build-tests` green.

Remaining validation (L1/L4 follow-ups, L5 inventory, L8 consumer wiring, 4 known test failures on trunk, ~20 `[QUESTION]` rows blocked on precursors) tracked as active **#031**.

---

## Migration notes (2026-04-21)

This archive was seeded by consolidating:
- `plans/backlog/ui-mockup-gaps.md`
- `plans/backlog/ui-dogfood-bugs-2026-04-21.md`
- `plans/backlog/transcript-trigger-context.md` *(active → #027)*
- `plans/backlog/phase-8-cancel-recording.md` *(active → #002)*
- `plans/backlog/issue-6-pill-panel-focus.md` *(active → #003)*
- `plans/backlog/model-download-ux-bug-research.md` *(active Stage B → #009/#024/#025/#036/#038)*
- `plans/backlog/streaming-output-delivery-mechanism.md` + `plans/backlog/pipeline-streaming-defer.md` *(merged active → #033)*
- `plans/PLAN_PHASES.md` *(slim summary kept as `plans/ROADMAP.md`; full file moved to `plans/_legacy/`)*
- `plans/central/PROGRESS.md` *(stale; deleted — `INDEX.md` is authoritative)*

Original source docs moved to `plans/_legacy/`, later deleted (`ui-mockup-gaps.md` kept at `plans/backlog/`).

---

## Archived 2026-04-22: 9 bugs + 3 refactors closed during dogfood run

Moved from active `BACKLOG.md` after landing. Full ticket bodies preserved — commit SHAs, root-cause notes, and scope decisions stay greppable by ticket ID.

**Bugs:** #001, #003, #004, #005, #006, #008, #040, #041, #044
**Refactors:** #026, #043, #031

---

### #001 — Hold-to-record leaks `÷÷÷÷` then drops transcript

`bug` · `P0` · `done` · `area: hotkey, pill`
*Updated 2026-04-21*

Holding `opt + /` typed `÷` into the frontmost app for the duration of the hold, then failed to paste the transcription. Fix landed across five commits; runtime verified via MV-HK-8..11 on DMG (2026-04-21). MV-HK-10's Input-Monitoring-revocation premise is stale for the post-5a architecture — `.cgSessionEventTap` can be satisfied by either Input Monitoring or Accessibility, and Accessibility carries the tap in practice (grant landed for paste synthesis via `ClipboardBatchOutput.swift:54`). Runbook annotated.

**Blocks:** #028
**Legacy:** `ui-dogfood-bugs-2026-04-21.md` #5

**Changelog**
- 2026-04-21 `fd9d47a` — HotkeyEvent adapter scaffold (no-op refactor)
- 2026-04-21 `ce6ba19` — standalone HotkeyEventTap + `CGEvent.tapCreate` swallows matching keyDown + auto-repeat + keyUp
- 2026-04-21 `4d5bf7f` + `4114614` — replaced symmetric `coordinator.toggle()` on hold with explicit `startIfIdle` / `stopIfRecording`
- 2026-04-21 `231df70` — pill `collectionBehavior` updated for full-screen-app visibility
- 2026-04-21 — runtime verified MV-HK-8..11 on DMG; MV-HK-10 runbook updated to reflect Accessibility-carries-tap reality

---

### #003 — Pill panel steals focus on click

`bug` · `P0` · `done` · `area: pill, output`
*Updated 2026-04-21*

Clicking the pill promoted Ninimma to frontmost, breaking the auto-paste target. Fix landed via full non-activating contract on `DraggablePanel` (`PillOverlayPresenter.swift:54-84`, `:236`): `.nonactivatingPanel` style bit + `canBecomeKey = false` + `canBecomeMain = false` (per Wispr Flow reverse-engineering). Existing AX-probe workaround (#1 fix) stays as belt-and-suspenders. Runtime verified via MV-NAP-1 on TextEdit + iTerm (2026-04-21) — no clipboard-only card, paste lands in the pre-click target app. MV-NAP-2 (menu-dismissal) and MV-NAP-3 (menu-bar stop path) not yet exercised but the panel-level contract is regression-guarded via three unit tests in `PillOverlayPresenterTests.swift:274-302`.

Sublime Text surfaced a separate regression (AX probe false-negative) during verification — tracked as #042, not a #003 concern.

**Legacy:** `backlog/issue-6-pill-panel-focus.md`

**Changelog**
- 2026-04-21 `936b07a` — full non-activating contract (`canBecomeKey/Main = false`) + 3 TDD tests (`testDraggablePanelCannotBecomeKey`, `…CannotBecomeMain`, `…StyleMaskRetainsNonactivating`) + MV-NAP-1..3 runbook entries
- 2026-04-21 — MV-NAP-1 runtime verified on TextEdit + iTerm; MV-NAP-2 / MV-NAP-3 deferred (unit tests cover the panel contract)

---

### #004 — Pill theme / window tint consolidation not reflected in build

`bug` · `P0` · `done` · `area: theming`
*Updated 2026-04-21*

Original claim was stale. Commit-log audit + runtime verification (2026-04-21) confirm the mockup-gaps G series landed and the Settings → General → Appearance card now has the intended three-picker model:
- **Theme** (Light / Dark / System) — master; persists as `AppTheme` (`Sources/PersonalScribeAppKit/Theme/AppTheme.swift:25-81`), propagates via `setAppTheme()` walking `NSApplication.shared.windows.appearance` (`GeneralTab.swift:528-533`).
- **Window tint** (Warm / Neutral) — conditionally shown only when effective scheme is Light (`showsTintPicker`, `GeneralTab.swift:270-284`).
- **Pill theme** (Dark / Light / System) — **intentionally independent** per the G.4 commit body ("pill independence invariant"). Not a bug.

Runtime verification: flipping Theme → Dark redrew the right pane in dark chrome and correctly hid the Window tint picker. Sidebar stayed light-on-dark — that residual visual leakage is tracked separately as **#040** (dark theme renders incorrectly across Settings surfaces), not a propagation failure.

**Legacy:** `ui-dogfood-bugs-2026-04-21.md` #7

**Changelog**
- `8e45f33` G.1 — `AppTheme` enum (Light/Dark/System, default Light)
- `f04ad4c` G.2 — drop `WindowTint.dark` case
- `76969af` G.3 — reroute former `WindowTint.dark` call sites
- `35adcd8` G.4 — Theme picker + conditional tint visibility + `nsAppearance` live-apply across open windows + `GeneralTabViewModelThemeTests`
- `0b70f1d` G.3 test fix — drop `WindowTint.dark` assertion
- `37f9384` G — backlog check-offs + resolution paragraph
- 2026-04-21 — audit + runtime verify on current build; residual sidebar-in-dark redirected to #040

---

### #005 — Launch-at-Login toggle doesn't prompt for permission

`bug` · `P1` · `done` · `area: settings, permissions`
*Updated 2026-04-21*

**Changelog**
- 2026-04-21 `2048b66` — `LaunchAtLoginServicing` protocol + `SystemLaunchAtLoginService` + status dot + info icon tooltip + `refreshLaunchAtLoginStatus()` on tab appear. 8 new unit tests (`LaunchAtLoginServiceTests`); filtered suite green. MV-LAL-1..5 runbook entries appended; runtime verification deferred to next DMG cycle (per batched-rebuild discipline).


Reframed after Codex scope pass 2026-04-21: the `SMAppService.mainApp.register()` / `.unregister()` calls ARE firing correctly (`GeneralTab.swift:569-571`). macOS does not natively prompt for Login Items registration — it's a silent system-level registration users verify in System Settings → General → Login Items. Current UX provides no feedback, errors are swallowed at `:574`, and the user reads the silent toggle as "nothing happened".

**Fix (scope-locked 2026-04-21 — keep simple):**
- **Status dot** next to the "Launch at login" checkbox — green when `SMAppService.mainApp.status == .enabled`, red otherwise.
- **Refresh status** on: (a) General tab becoming visible, (b) immediately after checkbox flip (post-register/unregister). Dot reflects reality, not hope.
- **Info icon** (ⓘ) next to the row — tooltip or popover explaining "Verify or change this in System Settings → General → Login Items".
- Inject `LaunchAtLoginServicing` protocol seam for testability; mirrors existing injected-closure pattern in `GeneralTabViewModel`.

**Deliberately NOT in scope** (keep it simple):
- No error alerts (dot shows truth).
- No System Settings deeplink button (info icon covers it).
- No packaging-gate UI logic.
- No optimistic-UI handling (just snap dot to real status post-call).

**Legacy:** `ui-dogfood-bugs-2026-04-21.md` #3

**Size:** ~30 source + ~50 test · 1 commit.

---

### #006 — Base-directory control is clunky; "Open in Finder" opens parent

`bug` · `P1` · `done` · `area: settings`
*Updated 2026-04-21*

Full "Base directory" label plus oversized buttons stacked onto a second line. `NSWorkspace.open` URL resolved to `~/Library/Application Support/` (parent) instead of `.../personal_scribe/`.

**Changelog**
- 2026-04-21 `a97e575` — compact single-HStack row with truncating path label + icon-only buttons; swap `activateFileViewerSelecting([url])` → `NSWorkspace.shared.open(url)` (root cause: `activateFileViewerSelecting` opens the parent folder with the target highlighted); inject `openInFinder` closure into `AdvancedTabViewModel`; 2 unit tests; MV-BASE-DIR-1..2 runbook.

**Legacy:** `ui-dogfood-bugs-2026-04-21.md` #15

---

### #008 — Sidebar mic footer is inert

`bug` · `P1` · `done` · `area: ui, sidebar, audio`
*Updated 2026-04-21*

Small "Microphone" label was hardcoded and inert. Decision locked (user, 2026-04-21): **status readout only** — show the currently-configured input device name with live updates; no interaction (clickable affordance stays with #037 title-bar accessory when that lands).

**Changelog**
- 2026-04-21 `4cf5a9b` — `MicrophoneFooterViewModel` observes `AudioInputDeviceProviding.selectedDeviceID` + `availableDevices()`; bridges `UserDefaults.didChangeNotification` for live updates on menu-bar-submenu selection changes; `refresh()` on `showWindow(_:)` catches hotplug. `UnifiedWindowView.microphoneFooter` renders device name with truncation. Shared `AVFoundationInputDeviceProvider` hoisted in `PersonalScribeAppMain` to feed both `StatusItemController` and `UnifiedWindowController`. 7 new unit tests; MV-MIC-FOOTER-1..3 runbook.
- 2026-04-21 `de7e4ae` — follow-up: update `UnifiedWindowControllerTests.makeController()` to pass `inputDeviceProvider: NoOpAudioInputDeviceProvider()` for the new init signature.

**Legacy:** `ui-dogfood-bugs-2026-04-21.md` #18 + `ui-mockup-gaps.md` unified-window-shell

---

### #040 — Dark theme renders incorrectly across Settings surfaces

`bug` · `P1` · `done` · `area: theming, ui, settings`
*Updated 2026-04-21*

In dark theme, the left sidebar pane rendered cream while the detail pane rendered dark, producing a half-light / half-dark shell. Root cause (2026-04-21 audit): `UnifiedWindowView` bound six shell surfaces (sidebar background `:97`, sidebar↔detail separator `:101`, brand-header text `:129`, microphone footer `:142`, about footer `:160`, detail backdrop `:181`) directly to `WindowTint.*`, which is a light-mode-only brand flavor (post mockup-gaps G). Dark `AppTheme` flipped `\.colorScheme` to `.dark` — inner tab content repainted correctly via `Palette.for(scheme:)`, but the shell stayed cream.

Fix: new `UnifiedWindowChrome` namespace (`Sources/PersonalScribeAppKit/UnifiedWindow/UnifiedWindowChrome.swift`) with four scheme-aware helpers (`sidebarBackground`, `detailBackground`, `chromeText`, `chromeSeparator`). Dark → `PersonalScribeTheme.Palette.dark.{surface, appBackground, primaryTextBase}`; Light → `windowTint.{secondaryBackground, primaryBackground, primaryText}`. Six leak sites in `UnifiedWindowView` rerouted through the helpers. 14 unit tests lock the truth table; full suite 870/870 green.

The Settings-sub-tab "black or mixed black/white backgrounds" described in the original ticket was not reproducible — the right-pane dark rendering in the 2026-04-21 audit screenshot looked correct; all visible leakage collapsed to the sidebar shell.

Acceptance:
- Dark theme shows consistent palette across window chrome, sidebar, and all Settings sub-tabs. → **Unit-tested via `UnifiedWindowChromeTests` (14 cases).**
- No visible white-on-dark or black-on-dark mismatches. → **Runtime verification (MV-DARK-SHELL-1..5) deferred by user decision 2026-04-21 — tests passing accepted as sufficient evidence for now. Runbook entries remain unchecked; re-verify on the next DMG rebuild cycle.**

**Changelog**
- 2026-04-21 (flint) — `UnifiedWindowChrome` helpers + `UnifiedWindowChromeTests` (14 cases) + 6-site reroute in `UnifiedWindowView` + `MV-DARK-SHELL-1..5` runbook entries; uncommitted in working tree; 870/870 suite green. Closed without runtime verify per user ("mark 40 done for now" 2026-04-21).

---

### #041 — Unified window pins to the space/screen it first opened on

`bug` · `P1` · `done` · `area: ui, unified-window, window-mgmt`
*Updated 2026-04-21*

Repro: on a full-screen app's space, launch Ninimma → window opened on that space. Close, exit full-screen, trigger Home — window re-opened on the former full-screen space instead of the current desktop.

**Root cause:** `UnifiedWindowController` was constructed with **no explicit `collectionBehavior`**. In an `LSUIElement` app using `makeKeyAndOrderFront(_:)` from the menu bar, AppKit's default keeps the window associated with the last space it displayed on. NOT a pill-overlay flag copy-paste (initial hypothesis) — the absence of `.moveToActiveSpace` was the bug.

**Changelog**
- 2026-04-21 `3a15cb3` — set `collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]`; add pure `reconciledFrame(for:activeScreenVisibleFrame:)` helper that re-centers when the persisted frame midpoint is off-screen; `showWindow(_:)` runs the reconciliation before `makeKeyAndOrderFront`. 6 new unit tests (2 collection-behavior regression guards + 4 reconciliation cases). MV-WINDOW-PIN-1..3 runbook.

---

### #044 — Pill responds to halo clicks; hit area doesn't match visible pill

`bug` · `P1` · `done` · `area: pill, ui`
*Updated 2026-04-21*

**Changelog**
- 2026-04-21 `5e560a4` — `PillOverlayView.size(for:)` + `PillOverlayPaneling.setFrame(_:animate:)` + bottom-center anchor preservation + cancel-card SwiftUI crossfade + response-card reanchor on pill frame change. 10 + 5 new tests (`PillOverlayViewSizeTests` + `PillOverlayPresenterTests`); filtered suite 32/32 green. MV-PILL-RESIZE-1..5 runbook entries appended; runtime verification deferred to next DMG cycle.
- 2026-04-21 (follow-up) — stub `setFrame(_:animate:)` in two peer `PillOverlayPaneling` conformances (`MenuBarFlowIntegrationTests`, `AppEntryPointTests`); import `PersonalScribeCore` + qualify `.apply(visibility: PillVisibilityState.x)` + fix arg order on parallel `PillOverlayViewModel` init sites to compile against live trunk state.


Floating pill overlay uses a fixed 280×60 `NSPanel` (`PillOverlayPresenter.swift:294`) sized for the widest variant (`.downloading` = 240×36); the hosting view fills the entire panel. In idle state (80×28) there is a ~200pt transparent halo around the visible pill that still registers clicks + drags — pill responds to taps that don't land on the visible shape. User-verified 2026-04-21.

**Fix direction (locked after Codex + Claude code-reviewer passes, 2026-04-21):** resize panel per state so panel size = visible pill size. No halo exists to click.

**Scope-locked decisions:**
- Animation owner: **A** — AppKit owns panel-frame tween (`setFrame(_:display:animate:)`); SwiftUI visibility spring at `PillOverlayView.swift:121` is removed. Single motion owner.
- Post-drag anchor: bottom-center preserved across resize.
- Cancel Card (`.cancelled`, 280×44): crossfade to a distinct surface rather than pill spring-morph — matches the "not a pill" framing at `PillOverlayView.swift:51`.
- Pill↔pill transitions: morph (size tweens; content swaps).
- Response card: reanchor to the **pill's** bottom-center (not panel frame). Moves with drag; stays put during pipeline resize (idle → listening → done).
- First show from `.hidden`: arrive at target state size (no idle-morph-in).
- Corner hit-testing: bounding-box-after-resize (pixel-perfect corners deferred as a follow-up).

**Implementation shape:**
- Pure `PillOverlayView.size(for: PillOverlayVisibility) -> CGSize` lookup over existing static sizes at `PillOverlayView.swift:39-54`.
- Extend `PillOverlayPaneling` protocol with `setFrame(_:animate:)`; update test spy at `PillOverlayPresenterTests.swift`.
- `PillOverlayPresenter` visibility sink: compute new frame + bottom-center anchor + `setFrame(..., animate: true)`. Special-case `.cancelled` ↔ any-pill as crossfade.
- `ResponseCard` anchor math: recompute relative to pill bottom-center (read from `PillOverlayPaneling.frame` at show time).
- Drop SwiftUI `.animation(.spring(..., value: model.visibility))` at `PillOverlayView.swift:121`; per-content animations inside each variant stay.

**TDD:**
- Pure helper — 10 cases for `size(for:)`.
- Presenter — frame transitions across visibility, bottom-center anchor preservation, cancel-card crossfade path, hidden→shown target size.
- Runbook `MV-PILL-RESIZE-1..5` appended to existing `ManualPillOverlayVerification.md`.

**Size:** ~150 source + ~120 test + 5 runbook entries · single commit.

**Legacy:** none — net-new ticket from 2026-04-21 dogfood session.

---

### #026 — Central storage / database layer

`refactor` · `P1` · `done` · `phase: 3` · `area: storage`
*Updated 2026-04-21*

Single `AppDatabase` owning GRDB connection pool + `DatabaseMigrator` + `TranscriptRepository` (the sole CRUD surface). Absorbed old Phase 3.D. Four independent `DatabaseQueue` handles on `transcripts.sqlite` collapsed to one. `TranscriptStoreJSONL` deleted outright; no backward-compat. `SQLiteTranscriptStore` / `SQLiteTranscriptReader` / `SQLiteMetricsReader` all deleted; metrics wiring consumes the shared `AppDatabase` via `SQLiteMetricsService(appDatabase:)`. Plan §7 validation grep sweep all clean. Full suite 855/855 green.

Plan at `plans/storage-database-layer.md` (landed in step 1.1 `5145cf7`).

**Design pass locked decisions** (fresh impl session should read the plan end-to-end, but highlights):
- `AppDatabase` = `struct` wrapping `any DatabaseWriter`; `DatabaseQueue` under the hood; single shared instance in `AppComposition`
- `TranscriptRepository.init(database:)` is the only CRUD surface; `write`/`read` raw-SQL closures are public with a code-review rule
- `TranscriptEntry` adopts `FetchableRecord` + `PersistableRecord` directly; shadow-struct decoders (`PersistedTranscriptEntry`, `MetricsTranscriptRow`) deleted
- JSONL sidecar nuked in Pass 2 (no shim, no back-compat); `v3_jsonl_bootstrap` becomes a PRAGMA-only no-op
- Read contract non-throwing; failures log via `PersonalScribeLogger`. Health-observable surface (`AsyncStream<StorageHealth>` + Advanced Settings "Database health" row + top-level banner) extracted to **#043**.
- Writes still throw; publishing thrown-write failures into the banner/Settings row belongs to **#043**.
- Metrics compat shim: none — `MetricsSnapshotStore.init(databaseURL:)` deleted in Pass 2 alongside the rest of the swap
- `PRAGMA user_version = N` kept in each migration
- `PLAN_PHASES.md` Phase 3.D absorbed (one-line edit alongside Pass 1's first commit)

**Blocks:** #011, #013, #014, #022, #027
**Legacy:** `PLAN_PHASES.md` Phase 3.D

**Changelog**
- 2026-04-21 (cedar) — plan drafted via 5 parallel drafting subagents; 9 atomic codex reviews (+ 2 Claude `10x-engineer:code-reviewer` fallbacks for silent codex runs); corrections absorbed (3→4 DB handles on `transcripts.sqlite`, v3 is a real data-moving migration not a no-op in the old code, per-migration error-identifier wrapping, single shared `AppDatabase` instance invariant, `all()` method added to repository, `makeMetricsService`/`makeMetricsReader` and `SQLiteMetricsReader` type added to Pass-3 deletion list)
- 2026-04-21 (cedar) — 10/10 `[QUESTION]` markers resolved across 2 review passes and locked into §3. JSONL-nuke + `storageHealth` observable were user-driven reframes during the second pass. Plan at `plans/storage-database-layer.md`, 193 lines, uncommitted; ready for Pass 1 implementation by a fresh session.
- 2026-04-21 (willow) — picked up for Pass 1 implementation; codex plan-review dispatched in parallel before coding.
- 2026-04-21 (willow) — codex review landed + absorbed. `storageHealth: AsyncStream<StorageHealth>` surface scope-split to **#043** (stream semantics unlocked; Pass 1 lands log-only swallowed-error behavior). Plan §3 + §7 + API sketch updated to reflect the split. Proceeding with Pass 1 plan-literal (snake_case `CodingKeys` on `TranscriptEntry` in Step 4 — pre-dogfood project, JSONL dying in Pass 2 is not a Pass-1 blocker).
- 2026-04-21 (willow) — **Pass 1 complete on trunk.** Four atomic commits: `5145cf7` (step 1.1: characterization test + Phase 3.D absorb + plan file), `db4ccde` (step 1.2: `AppDatabase` + migrator + error envelope), `6f06488` (step 1.3: GRDB conformance on `TranscriptEntry` via custom `init(row:)` + snake_case `CodingKeys`), `903ffd0` (step 1.4: `TranscriptRepository` CRUD surface). Full suite 870/870 green, 1 skipped. Subagents A/B ran in parallel worktrees off step 1.1, cherry-picked back; subagent C serial after A+B. No `[BLOCKED]` notes. Plan §7 validation list pending Pass 2/3 (those checkboxes are for post-swap/post-delete, not Pass 1).
- 2026-04-21 (willow) — **Pass 2 complete on trunk.** Four atomic commits: `3b1aaf5` (step 2.3: `SQLiteTranscriptStore` → 53-line shim over `AppDatabase` + `TranscriptRepository`; `TranscriptStoreJSONL` + `RingBuffer` + JSONL tests + JSONL bootstrap all nuked), `1d6446d` (step 2.1: `SessionCoordinator` + `SessionPipelineOrchestrator` accept `transcriptRepository:` in place of `transcriptStore:`), `69ed74f` (step 2.2: metrics readers consume shared `AppDatabase` via new `init(appDatabase:)`; `MetricsSnapshotStore.init(databaseURL:)` deleted outright), `cbcfaf3` (step 2.4: `AppComposition` now owns one shared `AppDatabase` + `TranscriptRepository`; `PersonalScribeAppMain.defaultTranscriptReader` consumes the shared repo via `TranscriptReading` conformance added on `TranscriptRepository`). Full suite 864/864 green (1 skipped). 3 parallel subagents (Session + Metrics + Shim+JSONL-nuke) ran off step 1.4, cherry-picked clean; Cluster 5+6 (composition rewire + `TranscriptReading` conformance) done in main session after cherry-pick. All three agents hit the stale-worktree-HEAD pattern (branched from pre-session `42fee7c`) and self-reset to `903ffd0` — no drift. No `[BLOCKED]` notes.
- 2026-04-21 (willow) — **Pass 3 complete on trunk.** Single commit `ab0ed95` (step 3.1: delete shim + `SQLiteMetricsReader` + `SQLiteTranscriptReader` + legacy readers). Pure-deletion pass plus `SQLiteMetricsService` rewrite to consume `TranscriptRepository` directly and absorb rollup math (word count / minutes saved / WPM) that used to live in the deleted reader. `AppComposition.makeMetricsService/makeMetricsReader` factory methods + `AppCompositionError` removed; `PersonalScribeAppMain` now builds `SQLiteMetricsService(appDatabase:)` inline off the shared `AppComposition.appDatabase`. Characterization test repointed at `AppDatabase(locator:)` setup; DDL pin still byte-identical. Full suite 855/855 green (1 skipped). Plan §7 validation grep sweep clean: no `DatabaseQueue/Pool` construction outside `Database/`, exactly one `AppDatabase(` site (the lazy `AppComposition.appDatabase` static), no `transcripts.sqlite` / `transcripts.jsonl` literals outside `Database/`, no legacy-type references in active code. **#026 complete.** Follow-up #043 (`storageHealth` observable + Advanced Settings "Database health" row) remains parked for its own design pass. Done in main session (no subagent — scope was methodical deletion + one rewrite; context already loaded).

---

### #043 — Database operation status observable

`refactor` · `P2` · `done` · `phase: 3` · `area: storage`
*Updated 2026-04-21*

Shared `DatabaseOperationObserver` (`@MainActor ObservableObject` with `@Published var current: DatabaseOperationStatus`) wired into `TranscriptRepository`. Every repo read/write records `.readSucceeded` / `.readFailed` / `.writeSucceeded` / `.writeFailed` after the operation settles. `AppComposition.databaseOperationObserver` is the shared instance, injected into the shared `TranscriptRepository`. Non-optional injection with a `NullDatabaseOperationObserver` default — no silent-prod-miss path.

**Scope reframe during design review** (Claude `10x-engineer:code-reviewer` pass): original plan §3 sketch of `AsyncStream<StorageHealth>` walked back to `@Published` + `ObservableObject` for SwiftUI ergonomics + automatic replay to late subscribers. "Health" terminology swapped for "operation status" — we track per-op outcomes (transient), not persistent DB health. No auto-heal logic needed (each op overwrites the previous status). FTS pattern-compile failures are just failed reads, not a special case. No UI row built in this ticket — drawer wired, consumers come later when a callsite actually needs to distinguish "no data" from "read failed".

**Blocks:** any future consumer that wants to react to storage failures (diagnostics panel, settings diagnostics row, telemetry shipper).
**Legacy:** scope-split from #026 during Pass 1; original plan §3 sketch superseded by v3 design.

**Changelog**
- 2026-04-21 (willow) — claimed for implementation. Codex review dispatched → silent-wrapper; re-issued via Claude `10x-engineer:code-reviewer` (clean review, 6 concerns, 0 silence). Review surfaced 3 real issues absorbed into v3: (a) optional injection silent-fail → non-optional with null default, (b) "degraded until restart" poisons UI on one bad FTS query → reframed as per-op status, no "health" language, (c) plan §3's `AsyncStream` → `@Published` for SwiftUI ergonomics (locked divergence after user sign-off).
- 2026-04-21 (willow) — landed on trunk as `a5a841a` (background subagent; types + protocol + null + real observer + repo wiring + composition + tests) + `91ea8fa` (main-session fixup for Swift 6 strict-concurrency on the test class — `@MainActor` + synchronous `makeHarness`; subagent's worktree compiled under looser rules). Full suite 884/884 green (1 skipped). Induced-failure test uses `search(query: "\"\"\"")` — GRDB's FTS5 pattern compilation throws on punctuation-only raw patterns, flowing through the existing catch → `.readFailed`. No new test-only seams.

---

### #031 — Central-layers refactor: validate remaining Stage 2/3 work

`refactor` · `P2` · `done` · `area: architecture`
*Updated 2026-04-21*

Audited 2026-04-21 against `plans/central/INDEX.md` (row-by-row) + current `Sources/` tree. All 9 layers' Stage 2 / Stage 3 claims verified with file+line evidence. Two minor drifts corrected in this pass: Row 2 Storage (duplicate `BaseDirectoryPath` claim stale — only at `AppConfig.swift:9`); Row 8 Metrics (Home-tab consumer landed in `a5ccae2`). `STAGE_3_DELETION.md §3c` L1/L2 cross-layer callout marked resolved.

4 test failures previously listed in (deleted) `PROGRESS.md` all pass on trunk: 3 `AppStoreTests` + 1 migrated to `ClipboardBatchOutputTests` (`PasteInjector` itself deleted in L1 Stage 3 `695d4d7`; test fixed in `3d7e1cc`). Flaky `NotesViewTests.testSearchFieldBindingDelegatesToViewModel` no longer exists in `Tests/`. No residual work or follow-up tickets — blocked-on-precursor items for L4/L5/L6/L7 already tracked in `STAGE_3_DELETION.md §3b`.

**Legacy:** `plans/central/INDEX.md` + (deleted) `PROGRESS.md`

---

## Archived 2026-04-22: #009 closed as deferred (no code change)

Closed without a fix — re-read of the code invalidated the ticket body's claims. Archived for traceability; re-file as a concrete ticket if a user-observable symptom ever appears.

---

### #009 — FluidAudio model-download progress not surfaced (Stage B)

`bug` · `P3` · `done` · `phase: 3` · `area: models, session`
*Updated 2026-04-22*

**Closed as deferred 2026-04-21; archived 2026-04-22.** Ticket body claims turned out to be largely stale or hypothetical on code re-read:
- `DownloadUtils.ProgressHandler` is already wired end-to-end (Stage A + post-Stage-A commits); no gap.
- `PrivateModelDownloader` already deleted from tracked source.
- Phase mapping is lossy (`.listing` → `.downloading`, bytes zeroed) but not dogfood-visible. Accepted as-is.
- "Session-start race" is not actually a bug: `transcribe(_:)` awaits `prepare()` at `ModelAwareFluidAudioTranscriber.swift:126-127`, so audio captured during `.recording` is safely buffered and transcribed once prepare completes. The existing Record-Without-Transcribe status card (MV-RWT-1..4) surfaces the wait to the user. Gating `.recording` on prepare would regress this UX, not improve it.
- `modelArtifactsAreValid` heuristic (files-on-disk ≠ loadable) is a theoretical correctness gap — persisted-ready-sentinel would tighten it — but no actual user-observable failure has been reported. Re-file as a concrete ticket if/when the "Settings says downloaded, transcription fails" symptom ever appears.

**Legacy:** `backlog/model-download-ux-bug-research.md` Recommended-Path items 1 + 3

---

## Archived 2026-04-22: #019 closed as won't-fix (removed by user decision)

The feature was implemented at one point and then deliberately removed at the user's request. Backlog entry lingered as `open` past the removal; closing it to match code reality.

---

### #019 — Triple-tap ⌥ emergency quit

`feature` · `P3` · `done` · `phase: 3` · `area: hotkey`
*Updated 2026-04-22*

**Closed as won't-fix 2026-04-22.** Triple-tap emergency-quit path was implemented then removed at user's request; no symbols remain in `Sources/` or `Tests/` (grep for `tripleTap` / `emergencyQuit` / `triple-tap` = 0 hits). Removal is codified in `Tests/PersonalScribeAppKitTests/ManualHotkeyVerification.md` MV-HK-4 — accidental triple-taps now surface as "recording started", never "app terminated". Re-file only if the user reverses the decision.

**Stale artifact flagged at close (not fixed):** `Sources/PersonalScribeAppKit/Settings/GeneralTab.swift:338` description still contains the clause "Emergency quit remains fixed." — cosmetic, deferred to a separate polish pass.

**Legacy:** `PLAN_PHASES.md` Phase 3.I + BACKLOG P3 #7

---

## Archived 2026-04-24: #076 shipped (direct-to-done, never filed open)

Surfaced in conversation as "speaker output bleeds into the mic." Options weighed (AEC, reference cancellation, ducking, media-key pause) against a simple system-mute toggle; user picked the simple path. Design pass → Codex review round 1 (simpler plan) → Codex review round 2 (walked back to CoreAudio for aesthetics; rejected — AppleScript sidesteps device-identity / notification-route concerns that CoreAudio reintroduces). Landed as one commit after manual verification.

---

### #076 — Mute system audio while recording

`feature` · `P2` · `done` · `area: audio · settings`
*Updated 2026-04-24*

Settings → General → Behavior toggle (default off). When on, `AVAudioCaptureService` calls `SystemAudioMuter.muteIfNeeded()` before engine start and `restoreIfNeeded()` on every capture-end path (stop, start-failure, runtime error, consumer cancel). Menu-bar Quit routes through `coordinator.stopIfActive()` first so the mute restore fires before process exit.

Muter drives the OS-level volume flag via `NSAppleScript` (`set volume output muted ...`) — the same flag the F10 mute key writes. Route-independent, covers media + alerts + notifications, no per-device CoreAudio tracking. Failure policy is log-and-continue: read failure skips the mute entirely (safer than caching `false` and unmuting a pre-muted machine); write failures are silent (user's ears are the feedback channel).

**Accepted scope:** force-quit / crash / SIGKILL during recording leaves the machine muted (user unmutes manually). Clean-quit path covered by the prequit handler.

**Commit:** `89ab9de` — muter (6 unit tests) + capture service wiring (4 lifecycle tests) + preference (5 round-trip tests) + menu-bar prequit handler + manual verification entry.

**Design artifacts:** `plans/investigations/2026-04-24-mute-system-audio-{prompt,codex,simpler-prompt,simpler-codex,simpler-codex-2}.md`

---

## Archived 2026-04-30: 9 bugs closed (Bugs section sweep)

Moved from active `BACKLOG.md` after landing across the 2026-04-22..2026-04-25 dogfood + plumbing window. Full ticket bodies preserved — commit SHAs, root-cause notes, and scope decisions stay greppable by ticket ID. Only #010 (drag-suppresses-tap E2E test) remains open in the active Bugs section.

**Bugs:** #002, #007, #039, #042, #071, #072, #073, #075, #077

---

### #002 — Esc during recording acts like Stop, not Cancel

`bug` · `P0` · `done` · `area: session, pill`
*Updated 2026-04-22*

Esc transcribes + pastes + offers Undo instead of true-discarding. **Decision locked 2026-04-22:** spec-literal — Esc **and** ✕ both truly discard (no transcribe, no paste). Pause/resume pill affordance split out to #070; hold-to-record path out of scope (separate pill, no Esc/✕).

**Implementation surface** (from `plans/_legacy/backlog/phase-8-cancel-recording.md`):
1. `Sources/PersonalScribeSession/Pipeline/Contracts/SessionPipelining.swift` — add `func cancelCapture() async`.
2. `Sources/PersonalScribeSession/Pipeline/Orchestrator/SessionPipelineOrchestrator.swift` — stop capture actor, drop buffer, transition `.recording → .idle` (skip `.transcribing`).
3. `Sources/PersonalScribeSession/SessionCoordinator.swift` — public `cancelRecording() async` calling `pipeline.cancelCapture()` + pasteboard snapshot restore.
4. `Sources/PersonalScribeAppKit/Composition/PersonalScribeAppMain.swift` — wire Esc + ✕ to `coordinator.cancelRecording()` (currently both route through `toggle()`).
5. Tests at each layer; update `ManualPillOverlayVerification.md` MV-PUX-10/11/14 to assert "no transcript is pasted" on Cancel Card flow.

**Legacy:** `ui-dogfood-bugs-2026-04-21.md` #12 + `plans/_legacy/backlog/phase-8-cancel-recording.md`

**Scope cut:** the ticket body listed "wire Esc + ✕ both to cancel". The ✕ glyph is visual-only today (no distinct tap region — the whole pill fires `onTap → toggle()`). Adding a hit-test carve-out for ✕ would be thrown away under #070, which replaces ✕ with a pause/play button. Esc is the only interactive discard path post-#002; ✕ becomes tappable under #070.

**Changelog**
- 2026-04-22 `1c2f37f` step 2.1 — `SessionPipelining.cancelCapture()` + `discardActiveCapture()` helper: stops engine, drops buffer, publishes `.idle` directly. Skips `.transcribing`, transcriber, and output sink entirely. 4 tests incl. `testCancelCapturePathNeverPublishesTranscribing` pinning the stream invariant.
- 2026-04-22 `d2c57b7` step 2.2 — `SessionCoordinator.cancelIfActive()` mirroring `stopIfActive()` shape: handles `.recording` or `.holdRecording`, no-op from non-active states. 3 tests.
- 2026-04-22 `5e1f7fe` step 2.3 — Esc handler in `PersonalScribeAppMain` calls `cancelIfActive()` instead of `toggle()`. Pill's `viewModel.cancel()` still fires for visual feedback; Phase 5 clipboard-restore on Undo becomes a no-op (no paste happened).
- 2026-04-22 `90af8c6` step 2.4 — MV-PUX-10/11/14 updated with the #002 no-transcript invariants; "Known spec deviations" section refreshed.
- Full suite: **917 tests, 1 skipped, 0 failures.**
- Runtime verification deferred to next DMG rebuild — MV-PUX-10/11/14 cover the primary invariants.

---

### #007 — Model labels ("Parakeet TDT", "Parakeet CTC") are opaque

`bug` · `P2` · `done` · `area: settings, models`
*Updated 2026-04-22*

Size alone doesn't explain the difference. Add one-line description or info popover per row; tighten row density so multiple models fit without scrolling.

**Legacy:** `ui-dogfood-bugs-2026-04-21.md` #13

**Scope shape locked 2026-04-22:** BOTH inline description AND a popover (not either-or). ⓘ icon next to display name; popover top shows Speed + Accuracy (relative-bar + label) + Size (actual bytes); then Architecture / Repository / Revision / Parameters. Ratings are computed-relative — ranks derived at render time from `ModelPerformance` benchmarks on each descriptor, no hardcoded label-per-model map.

**Changelog**
- 2026-04-22 `457ca81` step 1.1 — initial schema (walked back in 1.2): `ModelDescriptor.shortDescription` + `RelativeRating` enum + `speedRating`/`accuracyRating` fields. Enum-based approach put user-facing labels in code rather than the registry — user called it out.
- 2026-04-22 `0df02cd` step 1.2 — **pivot to published benchmarks.** Remove `RelativeRating` + rating fields + `TranscriptionEngine.displayName`. Add `architecture: String` (required), `performance: ModelPerformance` (optional `averageWER`, `rtfx`, `parameterCount`). Catalog populated from HuggingFace Open ASR leaderboard (v2: 6.05% WER, 3386 RTFx; CTC: 7.49%, 5345; v3: 6.34%, 3333). Label vocabulary falls out of rank, not hardcoded.
- 2026-04-22 `33d25a1` step 1.3 — `ModelInfoPopoverPresenter` computes relative rank within siblings, maps to 3 tiers via `(rank * 3) / N`. Speed labels "Fastest / Fast / Slow"; Accuracy labels "High / Medium / Low". Defensive: inserts self into candidate pool, ignores siblings missing the metric. 19 tests pin the label vocab, tier assignment, and edge cases.
- 2026-04-22 `b3f3278` step 1.4 — `AIModelsTab` row shows inline `shortDescription` under the display name + ⓘ info button wired to `ModelInfoPopover`. `SettingsCard` gained a `padding:` init parameter; AI Models rows use `compactCardPadding` (12pt vs 16pt) so all three registered models fit under the default 760×520 window without scrolling.
- Full suite: **954 tests, 1 skipped, 0 failures.**
- Runtime verification deferred to next DMG rebuild — `MV-AIM-1`/`6`/`7` cover the description line, popover content per-model, and "no scrolling" invariant.

---

### #039 — Settings tabs show stale state while window stays open

`bug` · `P2` · `done` · `area: settings, ui`
*Updated 2026-04-22*

Open the Settings window, navigate away from a tab (or keep it unviewed), trigger a state change elsewhere (e.g., an AI model finishes downloading), then return to the tab. The view still reflects pre-change state — e.g., a freshly-downloaded model continues to render "not downloaded" until the window is closed and reopened.

Fix direction: each Settings sub-tab should either (a) subscribe to its underlying state stream so it reactively re-renders, or (b) trigger a refetch on tab activation. Prefer (a) where the view-model already owns a publisher; (b) as a fallback for tabs that don't.

Acceptance:
- Download an AI model while Settings → some-other-tab is visible. Switch to AI Models. Row shows "downloaded" without closing the window.
- No spurious re-fetches when switching between tabs whose state hasn't changed.

**Audit of Settings sub-tabs (2026-04-22):**
- `AIModelsTab` — `@ObservedObject` on `DefaultModelService` singleton. Needed a belt-and-suspenders refresh because the observed-object path can miss disk changes that bypass the service (e.g. external `rm -rf`). Fixed below.
- `GeneralTab` — VM is sole mutator for every preference (grep confirmed no external `persist()` callers for `PillVisibilityMode`, `WaveformDecayMode`, `PasteMode`, `WindowTint`, `PillAppearance`, `PillStyle`, `PasteRestoreDelay`, `PasteEnabledPreference`, `AppTheme`, `ShowInDockPreference`). `launchAtLogin` already refreshed on `.onAppear`. `currentSystemIsDark` KVO-observed. No further change needed.
- `AdvancedTab` — `baseDirectoryResult` only mutated via user "Change directory" action inside the VM; no external path.
- `PermissionsSubTab` — already does `.onAppear { viewModel.refresh() }` (template followed here).
- Top-level tabs (Home / Transcriptions / Modes) — VMs live in `UnifiedWindowController`, receive updates via streams even when off-screen; no gap.

**Changelog**
- 2026-04-22 `48423e0` step 1.1 — `DefaultModelService.refresh()` re-reads `isDownloadedHandler` for every registered model, flips `.ready` ↔ `.notDownloaded` to match disk truth. Preserves `.downloading` / `.loading` / `.failed`. Idempotent when disk matches published state. 5 new tests (`testRefreshPromotesNotDownloadedToReadyWhenModelAppearsOnDisk`, `testRefreshDemotesReadyToNotDownloadedWhenModelDisappearsFromDisk`, `testRefreshPreservesInFlightDownloadingStates`, `testRefreshPreservesFailedState`, `testRefreshIsNoOpWhenStateMatchesDisk`).
- 2026-04-22 `0e1f284` step 1.2 — `AIModelsTab.body` calls `.onAppear { service.refresh() }`. Manual-verification entries `MV-SETT-STALE-1..4` in `ManualSettingsVerification.md` pin the promote / demote / preserve-in-flight / preserve-failed invariants.
- Full suite: **925 tests, 1 skipped, 0 failures.**
- Runtime verification deferred to next DMG rebuild — MV-SETT-STALE-1..4 cover the primary invariants.

---

### #042 — AX probe rejects custom-drawn editors (Sublime), regressing auto-paste

`bug` · `P1` · `done` · `area: output, paste`
*Updated 2026-04-22*

Since the 2026-04-20 paste-target redesign, auto-paste was gated on `focusedElementHasCursor()` which only returned `true` for native-AX text elements (`AXInsertionPoint`/`AXSelectedText` readable, or role in `AXTextField`/`AXTextArea`/`AXComboBox`). Sublime Text's custom-drawn editor (role `AXGroup`/`AXUnknown`, no text attributes) failed the probe; VS Code / Electron / Chrome web forms suspected. Transcript landed clipboard-only, user had to ⌘V manually. Affected both hotkey and pill-click paths.

**Fix direction (locked 2026-04-22, Option 1 — PID inequality):** independent deep-reviews by 2 Claude agents + 1 Codex agent (`plans/investigations/2026-04-22-042-ax-probe-{claude,claude-2,codex}.md`) converged on the root cause. Of the 3 options, Option 2 (extended roles) was rejected unanimously (`AXGroup`/`AXUnknown` too generic). Option 3 (revert to bundle-ID) loses defense against `Ninimma-frontmost AND AX-focus-in-self` (Settings/Dock-icon paths). Option 4 (hybrid: bundle-ID primary + PID fallback) is Option 3 + Option 1 rescue — robust but more code. Picked Option 1 alone: single honest gate, smallest LOC delta, fixes every AX-stubborn app at once. Claude 1's Option 5 (probe OR bundle-ID) was rejected for a regression hole (AX probe succeeds on Ninimma's own `AXTextField` → OR pastes into self).

**Implementation:** swap `liveFocusedElementHasCursor` at `ClipboardBatchOutput.swift:220-259` for a PID check using `AXUIElementGetPid` on the system-wide focused element, compared against `ProcessInfo.processInfo.processIdentifier`. Semantic rename across probe closure seam (`FocusedElementCursorProbe` → `FocusedElementExternalityProbe`, `focusedElementHasCursor` → `focusedElementIsInAnotherApp`). Extracted pure helper `focusedElementIsInAnotherApp(systemWideFocusedPID:currentProcessPID:)` for unit testing. Rollback block + `attributeIsReadable` helper deleted.

**Depends on:** #003 (done) — PID defense only intact because panel-level `canBecomeKey = false` prevents pill-click from ever becoming the AX focus owner.
**Legacy:** none — regression of the 2026-04-20 redesign.

**Changelog**
- 2026-04-22 — 3 independent agent reviews (Claude general-purpose + Claude code-reviewer + Codex via manual CLI prompt) landed. Root cause confirmed; 5 options mapped (3 from ticket + Option 4 hybrid + Option 5 OR). Option 1 locked after reviewers dissected Option 5's self-paste hole and Option 4's marginal robustness edge over Option 1. Investigation reports at `plans/investigations/2026-04-22-042-ax-probe-{claude,claude-2,codex}.md`.
- 2026-04-22 (source landed, uncommitted) — `ClipboardBatchOutput.swift` rewritten: live probe body replaced with PID inequality via `AXUIElementGetPid`; pure helper extracted for tests; rollback block + `attributeIsReadable` deleted; typealias + closure + method renamed for semantic honesty. 13 existing tests renamed (closure param + 5 method names), 3 new unit tests for the pure helper. Filtered suite 16/16 green (0.015s). `MV-AX-042-1..5` runbook entries appended to `ManualPillOverlayVerification.md` — covers Sublime, VS Code, Chrome web form, TextEdit/iTerm regression guard, and self-focus-skip path. Runtime verification deferred to next DMG cycle per batched-rebuild discipline.

---

### #073 — Settings "Launch at login" info icon: tooltip doesn't show + click is no-op

`bug` · `P3` · `done` · `area: settings, ui`
*Updated 2026-04-24*

**Symptom (user, 2026-04-24):** The `ⓘ` info icon next to the "Launch at login" toggle in Settings → General → Application has neither discoverable behavior:

- Hovering doesn't surface the tooltip ("Verify or change this in System Settings → General → Login Items").
- Clicking does nothing.

User has no way to learn what the icon is for.

**Root cause (hypothesis, not verified):** In `Sources/PersonalScribeAppKit/Settings/GeneralTab.swift`'s `applicationCard`:

```swift
Image(systemName: "info.circle")
    .foregroundStyle(.secondary)
    .help("Verify or change this in System Settings → General → Login Items")
```

Two problems:
1. `.help(...)` attaches a tooltip but SwiftUI may not reliably fire hover events on a plain non-interactive `Image`. Wrapping in a `Button` or giving it `.hoverEffect` / `.contentShape` may be required.
2. There is no tap action at all — the icon has no `Button` or `onTapGesture`. Click genuinely does nothing because nothing is wired.

**Fix directions (pick one, locked after brief):**

- **A. Make the icon an actionable button** that opens `x-apple.systempreferences:com.apple.LoginItems-Settings.extension` (or the equivalent `NSURL` for macOS 14+). Tooltip as secondary info. Best UX — turns the discoverability hint into a one-click fix path.
- **B. Tooltip-only, but make it work.** Wrap in a non-clickable `Button` with `.buttonStyle(.plain)` or attach `.contentShape(Rectangle())` + `.onHover` to force the hover region. Preserves the "info icon is just informational" framing but still no click action.
- **C. Remove the icon entirely.** If we can't both educate the user AND give them a click target cheaply, drop it and inline the guidance as caption text under the toggle. Ugly but honest.

Recommend **A** — active affordance, zero ambiguity, the destination is a real system surface the user needs.

**Repro:**
1. Open Settings → General.
2. Hover the `ⓘ` icon next to "Launch at login".
3. Observe no tooltip appears.
4. Click the icon. Nothing happens.

**Legacy:** none — net-new bug from 2026-04-24 dogfood.

**Changelog**
- 2026-04-24 `10bcc6a` Fix A landed: `.onTapGesture` on the `info.circle` Image opens `x-apple.systempreferences:com.apple.LoginItems-Settings.extension` via `NSWorkspace.shared.open(...)`. Tooltip text updated to "Open System Settings → General → Login Items". `.help(...)` kept as a fallback for the fraction of hover events SwiftUI honors on bare `Image`s. Same inline-icon + `.onTapGesture` pattern as the Background mode info icon landed in the preceding commit.
- Runtime verification deferred to next DMG rebuild — tap should open the Login Items pane of System Settings.

---

### #072 — Paste to cursorless surface silently drops clipboard too

`bug` · `P0` · `done` · `area: output, paste, clipboard`
*Updated 2026-04-24*

**Landed (2026-04-24, `8d06afc`):** Fix direction D — opt-in restore. New `ClipboardRestoreEnabled` pref defaults to `false` → transcript stays on clipboard indefinitely, structurally preventing the silent-drop symptom. Paired with `restoreSnapshotIfUnchanged(_:token:)` changeCount guard (for users who opt restore ON) so the delayed restore skips if anything has written to the clipboard since our transcript landed — handles sequential-recording + user-Cmd+C + external-app-write races. Auto-paste toggle (replacing `PasteMode` picker + unwired `PasteEnabledPreference`) defaults to `true`. Slider default bumped 0.5s→3.0s, max 5.0s→10.0s. Settings UI consolidated into a single "Transcribe output" section with an adaptive summary caption. `PasteboardSnapshotService` + `ClipboardBatchOutput.savedItems` unified into one service (pre-empts the #074 anti-pattern example). Unverified build-wise at commit time — Santa manifest popup blocked iterative verification; user confirmed paste works in the DMG after allowlisting.

**Residual UX gap (not a bug, not fixing now):** when auto-paste is on, paste is posted via `CGEventPost`, and the target surface has no cursor, the event goes to /dev/null — no visual hint to the user that they should press `Cmd+V` manually. The notice card only fires when paste was SKIPPED, not when it was posted-but-not-received. Transcript is still on the clipboard so `Cmd+V` works; discoverability is the gap. Live with it for now.

**Symptom (user, 2026-04-24):** When the frontmost surface has no text cursor to receive a paste (e.g., Finder window, a dialog with focus on a non-text control, a web page that doesn't trap `Cmd+V`), the paste silently no-ops AND the clipboard ends up empty. The transcript lands in history but is not recoverable via `Cmd+V` — user has to copy it manually from the Transcriptions tab. From the user's vantage this reads as "nothing happened" until they discover the history entry.

**Root cause (tentative, pre-investigation):** `ClipboardBatchOutput.deliverBatch` in `Sources/PersonalScribeAppKit/Output/ClipboardBatchOutput.swift:78-137`:

1. `savePasteboard()` snapshots the user's pre-recording clipboard (line 85).
2. Transcript is written to the pasteboard (line 89).
3. PID externality probe (#042) says focus is in another app — green-lights paste.
4. `pasteShortcutPoster()` posts `Cmd+V` via `CGEventPost`; returns `true` because the event was posted, not because any surface accepted it (line 126).
5. `scheduleRestore(restoreDelay)` unconditionally restores `savedItems` after ~500ms (line 130).
6. If the target surface had no cursor, step 4's `Cmd+V` went to `/dev/null` but step 5 still ran. Clipboard is now back to pre-recording state. Transcript only survives in SQLite history.

The root problem is that Ninimma cannot observe whether the posted `Cmd+V` was consumed by a text surface. `CGEventPost` is fire-and-forget at the HID level; AX round-trip to check "did text get inserted?" is racy and app-dependent.

**Fix directions (none locked — want investigation):**

- **A. Never auto-restore.** Always leave transcript on clipboard after paste. Simplest, eliminates data loss, but loses the "preserve user's clipboard" convenience. Essentially re-opens #018 scope at the default-off end.
- **B. Pre-paste target probe.** Before `pasteShortcutPoster()`, probe the focused AX element for text-editability (e.g., `AXRole` in text-editable roles, or writable `AXSelectedText` / `AXInsertionPoint`). If not text-editable, skip the paste attempt and return `.clipboardOnly` so the "Copied · ⌘V to paste" notice shows. Risk: this is exactly the under-inclusive probe that #042 ripped out for custom-drawn editors (Sublime/VS Code). Any tighter probe would regress #042.
- **C. Post-paste verification.** After posting `Cmd+V`, poll AX for "did text get inserted at the focus target?" within a short window; cancel the scheduled restore if we can't confirm insertion. Costs complexity + AX-permission dependency + still racy for apps that accept `Cmd+V` asynchronously.
- **D. Opt-in restore policy.** Flip default: leave transcript on clipboard by default; only restore if user enables "Preserve clipboard after paste" in Settings. Solves the data-loss problem at the cost of "my clipboard got clobbered" returning as the default UX — but that's the opposite complaint and less severe than silent data loss.

My read: **A or D** is the right default. B re-introduces the #042 regression. C is complexity for a heuristic. Needs user decision before locking.

**Depends on:** #042 (externality probe — the PID check is load-bearing; any fix here must stay compatible). Interacts with #018 (configurable restore delay — the fix may make the delay setting irrelevant if restore is default-off).

**Repro (user):**
1. Start a recording.
2. Switch focus to a Finder window (no text field focused) or any surface without a text cursor.
3. Stop recording.
4. Observe: pill confirms "Copied · ⌘V to paste"; press `Cmd+V` in a real text editor → paste is empty. Transcript is present in the Transcriptions tab.

---

### #075 — Hold-to-record + too-short recording wedges hold path

`bug` · `P1` · `done` · `area: session, pill, hotkey`
*Updated 2026-04-24*

Hold the recording hotkey for <1s, release. Orchestrator published `.error(.recordingTooShort)` (`SessionPipelineOrchestrator.swift:434-445`). Pill rendered the "Recording too short." error state, but subsequent hold-to-record presses did NOT start a new hold session — dead hotkey until user tap-started via pill click or tap-hotkey. Tap path re-armed the state machine; hold path alone didn't. User also observed tap-hotkey + pill-click paths wedging from `.error` too — broader than just hold.

**Root cause (user-identified):** "Recording too short" was misclassified as an error. It's a normal pipeline shortcut (nothing to transcribe), not a failure. The wedge was emergent from `.error` being a sticky state with inconsistent recovery paths per entry point; the double-render was from two surfaces (pill + card) both observing `.error(.recordingTooShort)`.

**Fix direction:** reclassify. New `SessionState.shortExit` non-error terminal case, display-maps to `.idle` so every entry-point guard accepts it as startable. `PersonalScribeError.recordingTooShort` deleted. Pill flips straight to idle (no chip, no message — the short hold itself is the signal); card renders nothing for `.shortExit`.

**Changelog**
- 2026-04-24 `597055e` step 1.1 — `SessionState.shortExit` case + `SessionCoordinator.displayState(for:)` maps `.shortExit → .idle` (same pattern as `.completed`). All exhaustive switches across Orchestrator, AppStore, AppStoreSnapshot, StatusItemController, StatusItemMenuModel, RecordingStatusCardDriver updated to route `.shortExit` alongside `.completed` / `.idle`. Test: `testShortExitDisplayStateMapsToIdle`.
- 2026-04-24 `c89a6d8` step 1.2 — Orchestrator at `SessionPipelineOrchestrator.swift:434` publishes `.shortExit` instead of `.error(.recordingTooShort)`. Kills the wedge by construction across hold/tap/click entry points. Tests: `testShortRecordingPublishesShortExitWithoutTranscribing`, `testShortRecordingPublishesShortExitWithoutCallingTranscriber`, `testStartHoldIfIdleFromShortExitEntersHoldRecording` (wedge regression).
- 2026-04-24 `6d89cd5` step 1.3 — Initial approach: AppStore emits `.error(message:)` chip for 1.5s. (Superseded by step 1.7 — chip dropped entirely per user.)
- 2026-04-24 `13b6b0f` step 1.4 — Card-driver regression test: `testDriverEmitsNothingForShortExit`. Driver already returns `nil` for `.shortExit` by construction (error branch matches only `.error`, default branch returns nil).
- 2026-04-24 `6ebbc31` step 1.5 — Deleted `PersonalScribeError.recordingTooShort` and its `LocalizedError` branches. `PillOverlayViewModel.pillMessage` + `AppStore.pillMessage` no longer map it. Pre-existing error-visibility test rewritten to use `.resampleFailure`.
- 2026-04-24 `c8ac42d` step 1.6 — Manual verification `MV-SHORT-1..6` in `ManualHotkeyVerification.md`.
- 2026-04-24 `82eade2` step 1.7 — Dropped the too-short chip entirely. User feedback: reusing `.error(message:)` kept the misclassified framing in the UI layer and hit a pre-existing SwiftUI rendering quirk where error text persists past panel resize. `.shortExit` now flips pill straight to idle via normal `rederivePillVisibility`. Test renamed: `testShortExitFlipsPillStraightToIdle`.
- Dogfood verification 2026-04-24: user confirmed (a) hold-record works from `.shortExit` (wedge fixed across entry points), (b) response card no longer renders for short-hold, (c) pill flips cleanly to idle post step 1.7.
- Follow-up not filed: `.error(message:)` text-persistence in SwiftUI pill rendering is theoretically reachable via remaining real errors (`.micPermissionDenied`, `.transcriptionFailure`, etc.), but those are rare enough that this isn't worth pre-filing. File if/when observed in dogfood.

---

### #071 — Hold-to-record intermittently stuck after release (start/stop async race)

`bug` · `P0` · `done` · `area: session, pill, hotkey`
*Updated 2026-04-22*

**Symptoms (user, 2026-04-22):** On the global hold-to-record hotkey, release *sometimes* fails to stop the session. Hold-pill stays visible with no affordance to dismiss. Pressing Esc opens the default (toggle-mode) recording pill in the background while the stuck hold-pill remains. Second Esc shows the Cancel Card / Undo. Works most of the time — intermittent.

**Root cause (consensus from 4 independent agent investigations 2026-04-22 — 2× Claude + 2× Codex):**

Async race between hold-start and hold-release `Task`s (`Sources/PersonalScribeAppKit/Composition/AppComposition.swift:109-118`). `startIfIdle()` calls `pipeline.toggleCapture()` which runs `capture.start()` *before* publishing `.recording` (`SessionPipelineOrchestrator.swift:159-190`). If the user's release lands during that window, `stopIfRecording()` reads `currentState == .idle` and silently no-ops (`SessionCoordinator.swift:117-122`). The start task then completes, publishes `.recording`, and the session is stuck recording forever — no release will ever fire.

Compounding architectural issue: three independent state holders with no shared "hold session" token:

| Holder | Field | Location |
|---|---|---|
| `GlobalHotkeyMonitor` | `isHolding: Bool` | `GlobalHotkeyMonitor.swift:80` |
| `SessionCoordinator` | `SessionState` (only `.idle/.recording/.transcribing/.error`) | `SessionState.swift:1-5` |
| `PillOverlayViewModel` | `visibility` (includes `.holdToRecord`) | `PillOverlayViewModel.swift:9` |

Hold-start pushes `.holdToRecord` directly to the view model via side-channel (`PersonalScribeAppMain.swift:157`), bypassing the store. The store has no way to emit `.holdToRecord` because `SessionState` carries no hold-ness. Hold-release has no direct pill-hide call — exit from `.holdToRecord` depends entirely on session state changing, which can't happen if the session is stuck `.recording`. Sticky-hold guard (`PillOverlayViewModel.swift:74-83`) then suppresses inbound `.recording` updates from the store, permanently trapping the pill.

**Why Esc compounds the breakage:** Esc handler (`PersonalScribeAppMain.swift:134-143`) gates on pill visibility (not coordinator state), calls `viewModel.cancel()` + `coordinator.toggle()`. If coordinator has somehow drifted back to `.idle`, toggle **starts a new session** → matches the "default recording pill appears" symptom. In-code comment at `:126-133` already flags this as a known gap (slated for #002).

**Fix direction (recommended — not locked):** `.holdRecording` as a first-class `SessionState` case. Hotkey layer calls `coordinator.startHold()` / `coordinator.stopHold()`. Store's `derivePillVisibility` emits `.holdToRecord` from `.holdRecording` — same channel as `.recording`. Kills the start/stop race (transitions now have a known source state), removes the side-channel pill push, and gives the store a single authoritative view of hold-ness. The "direct pill-hide on release" and "shared hold token" variants are subsumed by this.

**Depends on:** #002 (Esc true-cancel wiring — independent but complementary).
**Investigation reports:**
- `plans/investigations/2026-04-22-hold-stuck-session-codex.md`
- `plans/investigations/2026-04-22-hold-stuck-pill-codex.md`
- Parallel Claude reports (summarized inline above; not file-persisted)

**Changelog**
- 2026-04-22 `26122a6` step 1.1 — `SessionState.holdRecording` case + `AppStore.derivePillVisibility` emits `.holdToRecord` from `.holdRecording`; placeholder handling in all exhaustive switches. 2 new tests (`SessionStateTests.testHoldRecordingIsDistinctFromRecording`, `AppStoreTests.testHoldRecordingSessionStateDerivesHoldToRecordPillVisibility`).
- 2026-04-22 `b545753` step 1.2 — `SessionPipelining.startHoldCapture()` publishes `.holdRecording` **eagerly** before awaiting `capture.start()`. This is the core race fix: a concurrent hold-release now observes `.holdRecording` and routes to stop instead of no-opping on `.idle`. 2 new tests (`testStartHoldCaptureFromIdlePublishesHoldRecordingThenTranscribesOnStop`, `testStartHoldCapturePublishesHoldRecordingBeforeAwaitingCaptureStart` — uses `HangingStartCapture` to block `start()` and assert eager publish).
- 2026-04-22 `0facbba` step 1.3 — Coordinator Option A API: `startHoldIfIdle()` + mode-agnostic `stopIfActive()` (handles `.recording` OR `.holdRecording`). 6 new tests covering the new methods + guards.
- 2026-04-22 `e55d8f7` step 1.4 — Composition rewire: `onHoldStart → startHoldIfIdle`, `onHoldRelease → stopIfActive`. Deleted `onHoldStartVisibilityPush` side-channel in `AppComposition.makeGlobalHotkeyMonitor` and `PersonalScribeAppMain`. Deleted sticky-hold-to-record guard + `isShowingHoldToRecord` helper in `PillOverlayViewModel` — the store is now the single source of `.holdToRecord`. Runbook `MV-HOLD-1..5` appended.
- Full suite: **910 tests, 1 skipped, 0 failures.**
- Runtime verification deferred to next DMG rebuild — MV-HOLD-1..5 in `Tests/PersonalScribeAppKitTests/ManualHotkeyVerification.md` cover the primary repro (hold-release flakiness the user reported on 2026-04-22).

---

### #077 — AI Models tab shows non-ASR descriptors that fail on download

`bug` · `P2` · `done` · `phase: 3` · `area: settings, models`
*Updated 2026-04-25*

Resolved by **#024.10** — `AIModelsTab` now sections by `ModelKind` and filters `ForEach` to `ModelKind.allCases.filter(\.isEnabled)`, which is only `.asr` today. Per-kind rows inside each section come from `service.enabledModels(kind:)`. Non-ASR descriptors (streaming EOU, Qwen3, diarization) stay in the catalog for when #078 wires adapters, but don't surface in the tab until their kind flips to `isEnabled`.

Qwen3 f32/int8 rows (which have `kind: .asr`) still surface today and would fail download at the `FluidAudioRuntimeVariant` gate if tapped — the filter is by kind, not engine. The narrow filter (engine-level) lands with #078 Stage A when the Qwen3 adapter exists.

**Legacy:** session-generated 2026-04-25 from #024.6 catalog expansion follow-up.

---

## Archived 2026-05-01: 12 done features + refactors closed (Features/Refactors sweep)

Moved from active `BACKLOG.md` after landing across the 2026-04-22..2026-05-01 window. Full ticket bodies preserved — commit SHAs, scope decisions, and follow-up pointers stay greppable by ticket ID. Stale "open follow-up" lines cleaned at archive time: #028's `b1fc740` worktree commit landed on trunk as `d6bddc7`; #090's "invalid modes still register hotkeys" was already mitigated by `AppComposition.currentlyValidCustomModes` filtering at registration; #078's post-`10a81f0` RSS check was runtime-verified.

**Features (10):** #011, #013, #015, #016, #017, #024, #046, #078, #089, #092
**Refactors (2):** #028, #090

#027 (TranscriptEntry `modeId` + `trigger`) stayed active — `trigger` field deferred per locked design and #093 partially blocks on it.

---

### #011 — Per-row delete on transcription history

`feature` · `P1` · `done` · `area: ui, storage`
*Updated 2026-04-23*

Inline trash icon on hover (or swipe action). Must propagate through the transcript store, not just the view-model cache.

**Depends on:** #026 (clean repository delete path) — ✅ done
**Legacy:** `ui-dogfood-bugs-2026-04-21.md` #17

**Changelog**
- 2026-04-22 `bd5ceff` step 1.1 — `TranscriptRepository.delete(id:)` + `TranscriptStorageError.deleteFailed`; `TranscriptReader` gains `delete`. 2 tests (happy path, unknown-id → `deleteFailed`).
- 2026-04-22 `30b13f3` step 1.2 — `TranscriptionsTabViewModel.delete(id:)` with reload-on-success mirroring the edit pattern. New VM tests cover success + failure paths.
- 2026-04-22 `68ece00` step 1.3 — `TranscriptRow` trash-icon affordance on hover; wired through `TranscriptionsTab`. `MV-DELETE-1..3` runbook entries in `ManualTranscriptionsVerification.md`.
- Runtime verification deferred to next DMG rebuild — MV-DELETE-1..3 cover the primary invariants (hover reveal, row disappears, persists across relaunch).

---

### #013 — Edit transcripts (minimal notes capability)

`feature` · `P1` · `done` · `area: ui, storage`
*Updated 2026-04-22*

Scope cut 2026-04-22 after reviewing 5-stage overengineered plan: search already works on Transcriptions tab (substring filter at `TranscriptionsTabViewModel.swift:72-80`); dictate→store already works; only missing piece was **edit**. Tags, standalone NotesWindow, format toolbar, FTS5 upgrade, right-context-panel all deferred — file separate tickets if wanted after dogfood.

**Depends on:** #026 ✅
**Legacy:** `PLAN_PHASES.md` Phase 3.B (original NotesWindow scope — mostly deferred)
**Rejected plans (v1 overengineered):** `plans/013_notes_window/_archived_overengineered_v1/` — 5 stage plans + reviews from parallel planning pass.

**Changelog**
- 2026-04-22 `8affe56` step 1.1 — `TranscriptRepository.update(id:text:)` + `TranscriptStorageError.updateFailed` + `TranscriptUpdating` protocol. 2 tests (happy path, unknown-id → `updateFailed`) per no-speculative-abstraction discipline.
- 2026-04-22 `aef1a74` step 1.2 — `TranscriptionsTabViewModel.update(id:text:)` + `canEdit` flag; reload on success mirrors delete pattern.
- 2026-04-22 `ed1f612` step 1.3 — Transcriptions tab tap-to-edit sheet (plain SwiftUI `TextEditor`, no NSTextView bridge, no debounce). MV-EDIT-1..3 added to `ManualTranscriptionsVerification.md`.
- Filtered tests: **30 passing, 0 failures.**
- Runtime verification deferred to next DMG rebuild — MV-EDIT-1..3 cover save/cancel/persist-across-relaunch.

---

### #015 — OnboardingWindow

`feature` · `P2` · `done` · `phase: 3` · `area: ui, permissions`
*Updated 2026-04-22*

First-run permission flow with optional Accessibility step.

**Legacy:** `PLAN_PHASES.md` Phase 3.C

**Scope shape locked 2026-04-22 (minimal):** no new window — the unified window's `PermissionsSubTab` already replaced the pre-M4 `OnboardingWindowController` UI. The actual gap was that `OnboardingCompleted` was read on launch but never written, so the first-run auto-open of Settings → Permissions fired every time. Minimal scope closes that loop: observe the PermissionService; flip `OnboardingCompleted → true` the first time Mic + Input Monitoring both land as `.granted`; Accessibility is optional (paste-at-cursor has a clipboard fallback). Self-terminates after the flip — later revokes in System Settings don't re-trigger onboarding.

A net-new welcome/tour window would be fresh UX territory (hotkey walkthrough, mode switcher preview, pill behavior) and deserves its own ticket + mockup. Not in scope here.

**Changelog**
- 2026-04-22 `15c2f2e` step 1.1 — `OnboardingCompletionPolicy` (pure predicate) in PersonalScribeCore, 7 tests covering permutations. `OnboardingCompletionObserver` in PersonalScribeAppKit wraps a `PermissionService` + UserDefaults writer, self-terminates after first flip; 5 tests covering pending-stays-false, pre-granted-flip-on-start, mid-session-grant-flip, accessibility-only-noop, revoke-doesnt-re-trigger. `PersonalScribeAppMain` instantiates and starts the observer before the existing first-launch auto-open check — so re-install (perms already granted) skips the auto-open synchronously.
- MV-ONB-1/2/3 runbook entries in `ManualSettingsVerification.md` pin the flag-flip contract.
- Full suite: **966 tests, 1 skipped, 0 failures.**
- Runtime verification deferred to next DMG rebuild — MV-ONB-1..3 cover the primary loop.

---

### #016 — RAM-aware default model selection

`feature` · `P2` · `done` · `phase: 3` · `area: models`
*Updated 2026-04-22*

**Reframed 2026-04-22:** original ticket title was "Second model descriptor (parakeet-tdt-110m)" — stated intent was "for lower-RAM devices," but the registered catalog ID was a naming guess that doesn't match what NVIDIA publishes. The lightweight variant NVIDIA ships is `parakeet-tdt-ctc-110m` (Hybrid FastConformer-TDT-CTC, 110M params, 407 MB), already registered in `BuiltInModelCatalog` via Layer 6 work. So "the second model exists" is already satisfied — what's missing is the *RAM-aware default selection* the original ticket's motivation actually described.

**Scope (current):** on first launch (no persisted `ActiveModelDescriptor` in UserDefaults), inspect `ProcessInfo.processInfo.physicalMemory`. If below a threshold (≤ ~10 GiB, i.e. 8 GB Macs), default to the lightest registered model (`parakeet-tdt-ctc-110m`). Otherwise default to `parakeet-tdt-0.6b-v2` (unchanged). User choice always wins — once persisted, the RAM probe is never consulted again. Second and subsequent launches read the persisted selection.

**Legacy:** `PLAN_PHASES.md` Phase 3.F (originally scoped to "add the second entry")

**Changelog**
- 2026-04-22 `930330e` step 1.1 — `DefaultModelSelectionPolicy` — first attempt, over-engineered: generic "pick lightest registered model with declared parameterCount, tiebreak on size, fall back to baseline if no lighter candidate." 8 tests covering the defensive branches. Walked back in step 1.3.
- 2026-04-22 `da96525` step 1.2 — `DefaultModelService` convenience init gains `physicalMemoryBytes: Int64 = Int64(ProcessInfo.processInfo.physicalMemory)`, feeds into the policy, uses the result as `Preference<ActiveModelDescriptor>.default:`. Because Preference only consults `default:` when no value is persisted, this affects the fresh-install case only — persisted user choice always wins. 3 integration tests.
- 2026-04-22 `db791b0` step 1.3 — simplify policy + tests. Collapsed step-1.1's generic registry-scanning logic to a three-line `physicalMemoryBytes < threshold ? lightweight : baseline`; caller names the two candidates at the call site. 8 policy tests → 2. Rationale: defensive filtering was speculative complexity for catalog shapes that don't exist today; per global CLAUDE.md, three similar lines beat a premature abstraction.
- MV-RAM-1/2/3 runbook guidance in `ManualSettingsVerification.md` (cross-machine — harder to literally execute on a single dev box).
- Full suite: **971 tests, 1 skipped, 0 failures.**
- Runtime verification deferred to next DMG rebuild.

---

### #017 — Hotkey customization in Settings (collision detection)

`feature` · `P2` · `done` · `phase: 3` · `area: settings, hotkey`
*Updated 2026-04-24*

Shortcuts subsection exists (demoted from standalone tab via `a21e7b6`). Stage A landed 2026-04-24 (`9d01f84`): restore-default, plist-backed system-shortcut collision with disabled-warning state, intra-app reserved registry, live apply (no relaunch).

**Legacy:** `PLAN_PHASES.md` Phase 3.G

**Changelog**
- 2026-04-24 `9d01f84` stage A landed as one commit spanning 4 steps:
  - **1.1** `ShortcutsTabViewModel.restoreDefault()` + "Restore default" button on the Shortcuts card (disabled when already at `opt + /`). 1 test.
  - **1.2** `ReservedInAppHotkeys` registry (single seed: Esc). `HotkeyRecorder.handle(event:)` tightened to cancel only on plain Esc; `Cmd+Esc`/`Opt+Esc` now fall through to `rejectionReason` which calls the registry. 1 test.
  - **1.3** `SystemHotkeyRegistry` reads `~/Library/Preferences/com.apple.symbolichotkeys.plist` (pure-`parse` helper + file-loader); new `CaptureResult.capturedWithWarning(_, warning:)` case — `canConfirm` true, `warningMessage` exposed — triggers when the captured shortcut matches a *disabled* system shortcut. Enabled-system-shortcut collisions stay hard-rejected with the system name. 5 tests (3 registry, 2 recorder).
  - **1.4** `GlobalHotkeyMonitor.recordingHotkey: let` → `private(set) var`; new `updateRecordingHotkey(_:)` swaps binding + `resetState()`. `ShortcutsTabViewModel` gained an `onHotkeyUpdate` callback wired by `GeneralTab.init`'s default to `AppComposition.hotkeyMonitor.updateRecordingHotkey(_:)`. `requiresRestartNotice` + the shortcut card's `RestartRequiredCaption` removed (Background mode still uses the caption). 2 tests (swap + reset-in-flight).
- Runbook `MV-HK-1..4` appended to `Tests/ManualVerifications/ManualHotkeyVerification.md`.
- All 9 new tests passed on the other-laptop verification run; no #017-owned regressions.
- Per-mode keyboard shortcut shipped under #028 follow-up + #090.8 (`ModeDetailView.swift:300-333` recorder UI; `GlobalHotkeyMonitor.updatePerModeHotkeys`; `AppComposition.currentlyValidCustomModes` filter).

**Known limitations (not filed as follow-up):**
- Modifier-only binding (e.g. double-tap ⌥) is still deliberately unimplemented end-to-end — `HotkeyRecorder.captureModifierChange` rejects any `.flagsChanged` chord, and `GlobalHotkeyMonitor.handle(event:)` no-ops `.flagsChanged` with a comment pointing at future work. User confirmed 2026-04-24 this is acceptable; default `opt + /` is the intended binding. Reintroducing modifier-only input would need recorder + monitor gesture-machine changes in both layers.
- `ReservedInAppHotkeys`'s Esc entry is inert for plain Esc (captured by the recorder's cancel short-circuit first). Kept for `Cmd+Esc`/`Opt+Esc` rejection messaging and as scaffolding for future in-app hotkeys (#068, #070).
- Stale "right Option" strings in `PillOverlayView.swift:216` + `StatusItemMenuModel.swift:262,278` — cosmetic copy drift from the pre-`opt + /` spec; out of scope here.

---

### #024 — Model Stage B: per-row delete button

`feature` · `P2` · `done` · `phase: 3` · `area: models, settings`
*Updated 2026-04-25*

Per-row delete on the AI Models tab plus the ModelRow redesign + activate/download semantic split + catalog metadata refresh that fell out of dogfooding the delete flow.

**Scope locked 2026-04-24:** simple delete icon, no confirmation, no active-model block, no last-model rule. Disk usage shown inline. Pre-dogfood disposable.

**Implementation surface**
1. `ModelBoundTranscriberProvider.removeDownloadedFiles(_:)` — fs delete + cache reset.
2. `DefaultModelService.removeDownloaded(_:)` — public service method, publishes `.notDownloaded` after fs delete.
3. `ModelRow` redesign — replaced `Active` / `Set Active` / `Download` text buttons with a green-or-grey activity dot + compact `Activate` text button + trailing SF-Symbol icon button (`arrow.down.circle` ↔ `trash` based on `.notDownloaded` ↔ `.ready`). Inline disk size next to the short description. Transient phases keep the `StatusPill`.
4. AI Models tab wiring + Modes tab filter to hide modes whose voice model isn't on disk.

**Cleanup work that fell out of dogfooding**
- Separate `setActive` (pure persist+assign) from `download(_:)` (pure download with internal progress ingest). Modes tab + AI Models tab call the right method.
- `onSetActive` prewarm hook so activating a model immediately prepares it instead of surprising the user with a download on next launch.
- Settings tab uses a segmented `Picker` not `TabView`; added `.onChange(of: selectedSubTab)` to call `service.refresh()` on every re-entry to AI Models so out-of-band CLI deletes flip the row.
- Catalog metadata refresh — sizes corrected against HF tree API (110m: 407→217 MB, v3: 700→461 MB), v3 revision pinned, `repoFolderName` field added so the on-disk folder is sourced from FluidAudio's `Repo.folderName` not our `descriptor.id`.
- Catalog expansion — Streaming EOU (160/320/1280 ms), Qwen3 ASR (f32 + int8), speaker diarization. New `ModelKind` enum + `TranscriptionEngine` cases. Metadata-only — adapters not wired (see follow-up tickets).

**Legacy:** `plans/_legacy/backlog/model-download-ux-bug-research.md` Stage B

**Changelog**
- 2026-04-24 `73c0ba9` step #024.1 — `ModelBoundTranscriberProvider.removeDownloadedFiles` (fs delete + cache reset). 1 test.
- 2026-04-24 `829b776` step #024.2 — `DefaultModelService.removeDownloaded` + ModelRow redesign. 1 test + UI smoke.
- 2026-04-24 `98cf401` step #024.3 — split `setActive` from `download(_:)`. ModesTab filters non-downloaded modes.
- 2026-04-24 `d7da8f9` step #024.4 — Retry button rewired to `onDownload`; setActive test tightened (flipped stub + restored `$activeDescriptor` publication assertion); dropped dead `FakeModelService.downloadRequests`.
- 2026-04-25 `376f2ed` step #024.5 — `repoFolderName` field; sizes refreshed; v3 revision pinned `775be920…`.
- 2026-04-25 `0c55b16` step #024.6 — catalog expansion (6 new descriptors). New `ModelKind` + `TranscriptionEngine` cases.
- 2026-04-25 `e8cb597` step #024.7 — `onSetActive` prewarm wired; Settings tab `.onChange` refresh on AI Models re-entry. 1 test.
- 2026-04-25 `e73afa4` + `5014bbb` step #024.10 — per-kind active model state. `ModelKind.isEnabled` + `.displayName`; `Preference<[ModelKind: String]>` storage (replaces `Preference<ActiveModelDescriptor>`); `setActive(_ descriptor:)` evicts same-kind entries; `activeDescriptor(for:)` + `enabledModels(kind:)` API. Deletes: `ActiveModelDescriptor`, `ModelService` protocol, `AppKitActiveModeProvider`, `FakeModelService` + tests. Renames: `DefaultModelService` → `ActiveModelService` + test suite. `AIModelsTab` sections by kind. Resolves #077.
- Filtered suite passes clean across all sub-steps.
- Runtime verification deferred to next DMG rebuild — visual redesign + tab-switch refresh + activate prewarm.

---

### #046 — VAD auto-stop (2-stage)

`feature` · `P2` · `done` (Stage A + Stage B) · `phase: 3` · `area: audio, session, dictation`
*Updated 2026-04-24*

Auto-stop dictation after a configurable silence threshold. Stage A absorbed the Settings UI (toggle + threshold slider) on 2026-04-23. Stage B shipped same-week on 2026-04-24 as preference-gated opt-ins (warn-before-stopping grace + auto-stopped notification card), rerouted from the original pill-tint shape to the existing ResponseCard after user direction.

**Stage A (this ticket):** bundled Silero CoreML VAD (~1 MB), `processStreamingChunk` state machine (hysteresis + first-chunk gate built-in), preference-snapshotted-at-session-start, detached-task stop path. Two preferences: `VadAutoStopEnabled` (Bool, default `true`) + `VadSilenceDurationSeconds` (Double, default 2.5, range 1.0–5.0 step 0.5). Settings UI in `GeneralTab` → new "Auto-stop" card; threshold slider dimmed when toggle off. Hold-to-record does NOT get VAD. Preferences freeze at session start — mid-session toggle doesn't rescue the current recording; manual hotkey stop always wins. Bundled-model-load failure silently disables the feature for the process — NOT routed through `SessionState.error`.

**Stage B (shipped 2026-04-24 as preference-gated opt-ins):** two new Bool preferences, both default `false` — `VadShowStoppingWarning` enables a 0.8s grace window with "…stopping, speak to continue" shown in the ResponseCard; `VadShowAutoStoppedNotification` shows "Auto stopped. Update settings to change." (clickable link to Settings) for 2s after VAD-triggered auto-stop. Grace cancels on resumed speech (via new `VadEvent.speechResumed`) or on manual hotkey (immediate stop). Esc still means "discard recording" per #002 — unchanged. Pill remains untouched; both visuals live in the ResponseCard.

**Design lock (2026-04-23):**
- `VadProviding` (long-lived factory, holds CoreML model) + `VadSessionHandle` (closure-based per-capture handle) in `PersonalScribeVAD` module. Protocols avoid `mutating async` existentials; per-session state is struct-shaped inside the actor.
- Session state stays unchanged — no new `SessionState` case, no `SessionSnapshot` field, no `SessionCoordinator` public-API change. VAD is invisible from outside `SessionPipelineOrchestrator`.
- Stop-request path: `consumeCaptureStream` spawns a detached `Task { await coordinator.stopIfActive() }` on `.speechEnded`, continues draining buffers until capture-stop closes the stream. Rationale: inline `await stopIfActive()` from inside `captureTask` self-awaits `captureTask.value` and deadlocks — caught by codex design review ([`plans/investigations/2026-04-23-046-vad-design-codex.md`](./plans/investigations/2026-04-23-046-vad-design-codex.md)).
- Loop-local `vadAlreadyFired` gates second fires. Codex critique of the earlier `hasFired` inside session: redundant with loop boundary → moved to consumer.
- Lazy-load VAD model on first `makeSession` call, memoize result (loaded or failed). Composition-time load would hit `AppComposition.sessionCoordinator`'s static path — known launch-latency concern per #012.
- Provider silently returns `nil` handle on bundled-model-load failure. Orchestrator no-ops; Settings toggle remains visible (hidden capability mismatch acknowledged; documented in runbook).
- `#070` pause/resume assumed to tear down + recreate the capture stream — VAD re-arms naturally. If #070 keeps the stream alive during pause, VAD would continue monitoring a paused session → wrong. Dependency flagged on #070 body.

**Codex design review:** [`plans/investigations/2026-04-23-046-vad-design-codex.md`](./plans/investigations/2026-04-23-046-vad-design-codex.md) — caught the self-await deadlock blocker + simplifications (struct session, lazy load, silent-disable on failure).

**Step plan:**
- **1.1** protocols + bundled model + struct session + provider lazy-load + unit tests.
- **1.2** orchestrator consume-loop hook + settings UI + preference reader + AppComposition wiring.
- **1.3** `MV-VAD-1..5` runbook entries in `ManualVADVerification.md`.

**Changelog**
- 2026-04-24 `15e2496` Stage A landed as a single commit spanning all three steps. `PersonalScribeVAD` module (VadProviding/VadSessionHandle/VadEvent + FluidAudioVadProvider lazy-load + FluidAudioVadSession 4096-sample accumulator). Bundled `silero-vad-unified-256ms-v6.0.0.mlmodelc` (~1 MB). `SessionPipelineOrchestrator.consumeCaptureStream` snapshots handler + provider + prefs at session start, spawns detached Task on `.speechEnded`, keeps draining — no self-await deadlock. `GeneralTab` Auto-stop card (toggle + 1.0–5.0s slider, dimmed when off). 7 new tests incl. `testAutoStopHandlerCallingPipelineToggleCaptureDoesNotSelfDeadlock` regression-catcher for the codex-flagged issue. Full suite at A: 962 tests, 1 skipped, 0 failures. Runtime verified same day — user confirmed auto-stop works in DMG.
- 2026-04-24 `c689560` Stage B Phase 1+2 — Core types + orchestrator grace state machine. `VadPreferences` gains `showStoppingWarning` + `showAutoStoppedNotification`. `SessionSnapshot` gains `vadAutoStopGracePending: Bool`, `vadAutoStopGraceDeadline: Date?`, `vadAutoStopFireToken: UUID?` (producer-owned identity, consumers compare-against-last-seen — codex-recommended shape, replaces an earlier broken Bool latch). `VadEvent` adds `.speechResumed`. Orchestrator replaces Stage A's `vadAlreadyFired` bool with a `GracePhase` enum (idle / pending / resolved) + single actor-isolated `resolveGracePending(token:trigger:)` resolver. Token check guards against timer vs. cleanup race. Error + grace-clear land in the same publish per codex review #7. Grace duration injectable at init for tests (default 0.8s).
- 2026-04-24 `017d933` Stage B Chunk C (parallel subagent) — ResponseCard driver extension + link support. `StatusCardContent`/`StatusCardLink`/`StatusCardLinkAction` types. Priority-ordered `statusContent(...)` (error > warning > notification > record-without-transcribe). `ResponseCard` + `ResponseCardView` accept optional link range + tap handler; `AttributedString` renders the linked substring. `PillOverlayController` tracks `lastSeenVadFireToken` so each new fire-token renders the notification exactly once. 3 new driver tests.
- 2026-04-24 `a126b17` Stage B Chunk D (parallel subagent) — `GeneralTab` Auto-stop card collapsed layout. Threshold slider + two new toggles visible only when master `Auto-stop after silence` is on. VM gains `vadShowStoppingWarning` + `vadShowAutoStoppedNotification` published properties + setters mirroring the Stage A pattern.
- 2026-04-24 `ef023e4` Stage B Chunk E (main session) — composition wiring for the notification's Settings-deep-link closure. `PillOverlayController.openVadSettingsAction` flipped to a `var` with `setOpenVadSettingsAction(_:)` setter because the unified-window host is constructed after the pill controller in `PersonalScribeAppMain`; post-init injection. Bundle-model safety: new `testFluidAudioVadProviderLoadsBundledModelAndProducesSession` exercises the real bundle + CoreML load (guards Package.swift resource drift), plus debug-only `assertionFailure` in `FluidAudioVadProvider.init()`. Runbook MV-VAD-6..10 + reframed bundle-model gap as a build-time invariant.
- Full suite at B: **928 tests, 1 skipped, 0 failures.** Total delta: +4 VAD tests (grace timer, speech-resumed cancel, error-atomic publish, bundle-load) + 3 driver tests - existing count shifted from 962 → 928 due to Stage A test-scope trimming earlier the same day.
- DMG rebuilt + installed 2026-04-24. Runtime verification per MV-VAD-6..10 pending user confirmation.

**Legacy:** `plans/_legacy/BACKLOG_pre_migration.md` → "VAD auto-stop"

---

### #078 — Adapter layer for non-`parakeetTDT` model families

`feature` · `P0` · `done` · `phase: 4` · `area: transcription, models, architecture`
*Updated 2026-05-01*

Adapter layer for Qwen3 ASR, streaming EOU (parakeet-realtime), and offline diarization landed via the parallel-build → swap → delete plan in `plans/078_adapter_layer/`. Recipe-driven backbone is the only path; legacy `LegacyTranscriber` / `ServiceBackedActiveModeProvider` / `LegacyWorkflowMode` are gone.

**What landed (post-cutover, in commit-order):**
- Phases A–F (additive parallel build): `ModelLifecycle` / `Transcriber` / `StreamingTranscriber` / `SpeakerDiarizer` protocols, `RecipeWorkflowMode` + Codable schema + validator, `ModelBoundProcessorProvider`, four FluidAudio adapters, `RecipeBuilder`, `WorkflowModeRegistry` + `LegacyToggleMigrator`.
- Phase G cutover (`#078.29-31a/b`): orchestrator becomes recipe-driven; `AppComposition` + `ActiveModelService` swap to `ModelBoundProcessorProvider`; `SessionCoordinator` drops legacy `transcriberProvider` + `pipelineTranscriber` bridge.
- Phase H deletes (`#078.34-36`, commits `81a8492` + `5caf7c1`): legacy `LegacyTranscriber` / runtime-variant / `ServiceBackedActiveModeProvider` removed; `WorkflowModeRegistry` moved Session→Core for direct `AppStore` consumption; `ModelDescriptor.kind` becomes a computed accessor on `engine`.
- `#078.33` GeneralTab Settings toggle bridge to `WorkflowModeRegistry.mutateActiveOrFork(_:)` (commit `d00b8d6`). Auto-paste / Auto-stop / Restore-clipboard toggles fork active built-in mode into a custom recipe on first touch.

**Post-#078 regression hunt (2026-04-28 session):**
- `36e4867` — Phase 1-3 adapter lifecycle: `downloadIfNeeded()` (disk-only) on `ModelLifecycle`; activate-time prepare via `onSetActive`; `provider.evict(_:)` on the previously-active descriptor.
- `d622b6b` — path fix. Adapters bypass FluidAudio's `Qwen3AsrModels.download` / `AsrModels.download` (which mangle `to:`) and call `DownloadUtils.downloadRepo` directly. Manual `AsrModelVersion → Repo` mapping in the live Parakeet manager (`Repo` is non-Sendable, so a `ParakeetAuxiliaryRepo` shim wraps it).
- `967a9d9` — AI Models tab Delete button hidden on the active row; removal errors publish `.failed(message:)` to the chip.
- `3fe1caf` — `ModelDescriptor.auxiliaryRepoFolderNames`. 110m hybrid declares its CTC head; `removeDownloadedFiles` iterates aux folders; `downloadIfNeeded` pulls aux when variant matches.
- `848c095` — shared `FluidAudioDownloadProgressBroadcaster` + `FluidAudioProgressMapper` replaces four near-identical per-adapter broadcasters; AIModelsTab chip drops the percent (`"Downloading…"` label-only — FluidAudio's `URLSession.download(for:)` delegate fires too coarsely for smooth bar).
- `10a81f0` — **runtime memory eviction fix.** Process was hitting 4.77GB resident with 3.86GB MALLOC_LARGE because `SessionPipelineOrchestrator.makeProgressForwardingTask` captured `lifecycle` strongly via the for-await header AND `FluidAudioDownloadProgressBroadcaster` had no `deinit`. Each Activate switch left the previous adapter pinned forever. Fix: extract `let stream = lifecycle.modelDownloadProgress()` outside the Task body so the closure captures the AsyncStream value, not the adapter; broadcaster `deinit` calls `continuation.finish()` on outstanding subscribers. Together breaks the retention cycle. Runtime-verified post-`10a81f0`: process RSS tracks only the currently active model's footprint across Activate switches.

**Test status:** 1081 tests, 1 skipped, 0 failures. Tap-to-record + hold-to-record + Activate-switch + Download/Delete flows verified on 2026-04-27/28.

**Open follow-ups (filed separately):**
- `#078.39` — manual verification artefacts (Qwen3 entry in `ManualTranscriptionVerification.md`; streaming + diarizer checklists deferred until #056/#058/#061 ship UI consumers).
- `#088` — narrow FluidAudio model download to runtime-needed files (P2 refactor — Qwen int8 lands ~2.9GB for a 1.25GB runtime due to FluidAudio's `isMetadata` carve-out admitting `.bin/.json/.model` from any nested dir under subPath, scooping up v1 + `.mlpackage` siblings).

**Legacy:** session-generated 2026-04-25 from #024.6 catalog expansion follow-up.

---

### #089 — Modes editor (custom recipes, push-nav detail, autosave)

`feature` · `P1` · `done` · `phase: 3` · `area: modes, ui, recipes`
*Updated 2026-04-29*

User-facing editor for `customModes` in the unified window's Modes tab. Today the tab is read-only — surfaces the single hardcoded `WorkflowMode.dictation` built-in, no create / edit / delete. This ticket ships a complete cohesive Modes UX: empty list on first launch → tap `+` → preset popover → mode appears → tap row → push-nav detail with autosave-on-change.

**Design source.** `plans/089_modes_editor/` (CHECKLIST + BRIEF + DESIGN + IMPLEMENTATION). Locked premises in CHECKLIST.md.

**Scope.**
- Modes tab list shows `customModes` only. Empty on first launch (`WorkflowMode.dictation` stays in code as a fallback used when `customModes` is empty or `defaultModeID` points to a deleted mode — never rendered).
- `+` opens preset popover with four named presets: Dictation, Notes, Meeting, Streaming Dictation. Pick → row appended to `customModes`, push to detail.
- Detail surface: editable title, Realtime toggle, Voice model (read-only display + link to AI Models tab), Auto-stop on silence (toggle + threshold slider when on), Auto-paste, Restore clipboard, Identify Speakers (diarization), Delete this mode card at bottom.
- Drag-reorder rows; persists as `customModes` array order; menu-bar / pill switcher iterates this order.
- Two row glyphs: dot (current mode for next recording — set via menu-bar / pill switcher only) + star (user's default — set by tapping star on row).
- App start: current = default. If `defaultModeID` unset or stale → fallback to `WorkflowMode.dictation`.
- Push-nav detail with back arrow; autosaves every change; no Save / Cancel.
- Glyph fixed-by-preset (no glyph picker).

**Multi-language picker** — pending codex feasibility report (`plans/investigations/2026-04-28-multilang-feasibility-codex.md`, prompt at `2026-04-28-multilang-feasibility-prompt.md`). If FluidAudio supports per-call language hint, adds `language: String?` field on the transcriber processor and a Language picker in detail when active voice model is multilingual. If not, no picker.

**Out of scope** (deferred to follow-up tickets when those features land):
- Custom instructions / LLM model picker / Context fields → #020 / #021 / #022 territory
- Activate-for-apps rules → #057
- Per-mode keyboard shortcut → shipped under #028 follow-up + #090.8 (`ModeDetailView.swift:300-333`)
- Autocapitalize → #053 territory
- Playback during recording / Record-from-system-audio → #047 / #059
- Per-mode model override (mode picks language only; voice model stays globally selected via AI Models tab)
- Glyph picker

**Why now.** Post-#078, the recipe-driven backbone is shipped; `WorkflowModeDocument.customModes` exists, validators enforce shape, but the user-facing editor surface is missing. Without it, every mode-shape change requires a code edit. Also: AI Models tab surfaces streaming + diarization model rows whose "Activate" persists per-kind selection but never runs at session time (no recipe consumes those kinds today). #089 lands the recipe consumer.

**No phasing.** Ships as a single cohesive feature ticket. One commit at close. Future LLM / app-context features extend the editor in their own tickets when those features ship — not as "phase 2 of Modes editor."

**Legacy:** replaces stale `plans/PHASE_2_unified_ui.md` Step 2.6 (BLOCKED on Q.M5 since 2026-04-22). Q.M5 sub-questions (new-mode dialog fields, single-active vs multi-active, delete affordance) resolved 2026-04-28 grilling session.

---

### #092 — Speaker separation sensitivity (Relaxed / Balanced / Strict)

`feature` · `P2` · `done` · `area: transcription, modes, settings, ui`
*Updated 2026-04-30*

User-facing preset (`SpeakerSeparationSensitivity`: relaxed / balanced / strict) that translates into FluidAudio's `OfflineDiarizerConfig` knobs (`clusteringThreshold`, `minSegmentDurationSeconds`). Global pick in Settings → General; per-mode override on the Modes editor diarization card.

**Commits on trunk:**
- `fc989ca` `#092.1` — `SpeakerSeparationSensitivity` domain enum + `SpeakerSeparationParameters` (clustering threshold + min-segment duration; FluidAudio community-1 defaults at balanced).
- `3cdffdc` `#092.2` — global + per-mode wiring. `ProcessorSpec.diarizedTurns` gains `sensitivity: Parameter<SpeakerSeparationSensitivity>` (Codable backward-compat: missing field defaults to `.setting(PreferenceKeys.speakerSeparationSensitivity)`). `BoundProcessor.diarizedTurns` carries the resolved value. New `OfflineDiarizerConfigBuilder` translates preset → `OfflineDiarizerConfig`. `SpeakerDiarizer` protocol gains `applySensitivity(_:)` (default no-op). `FluidAudioOfflineDiarizerAdapter` invalidates the cached `OfflineDiarizerManager` on preset change. `GeneralTab` sensitivity card; `ModeDetailView` `SensitivityParameterPickerView` under diarization toggle.
- `3a44b73` `#092.3` — fix prewarm race that poisoned subsequent sessions. Codex root-cause: orchestrator-level `applySensitivity` lived in a `Task.detached` prewarm the live capture path doesn't await; short recordings raced past the prewarm so the fusion processor's `prepare()` short-circuited on the prior session's `hasPreparedModel = true` against a stale diarizer config. Fix: `DiarizedTurnTranscriptionProcessor` now carries the resolved sensitivity (via `BoundProcessor.diarizedTurns` at orchestrator line 645) and calls `applySensitivity` inside its own `prepare()` before the concurrent diarizer + transcriber prepare. Orchestrator-level call kept as belt-and-suspenders for the public `prepareTranscriber()` API path.
- `30381cf` `#092.5` — error reporter + pill stops rendering errors (errors now route to response card).

**Tests** (in tree as of trunk HEAD): `testEachPresetProducesAValidConfig`, `testNonBalancedPresetsDifferFromFluidAudioDefaults`, `testProcessAppliesSensitivityBeforePreparingDiarizer` (pinning the prewarm-race fix's ordering contract). Suite green: 1100/0 (per `3a44b73` commit message).

**Closed 2026-04-30:** runtime-verified on the other laptop — user could not reproduce the failure post-`3a44b73`/`30381cf`. Reopen if the regression resurfaces.

**Legacy:** none — net-new.

---

### #090 — Per-mode descriptor pinning

`refactor` · `P2` · `done` · `area: transcription, models, modes, recipes`
*Updated 2026-05-01*

Each mode can pin a specific `ModelDescriptor` instead of late-binding to whichever model is globally active. Lets the user have a "Japanese meeting" mode (Qwen3) and an "English dictation" mode (Parakeet) coexist; pinned modes survive a global active swap.

**Shipped 2026-04-29**, 8 cycles `0fbfdf5..f8f3961` + dogfood-verified on the Air (Tests 1/2/3 in `Tests/ManualVerifications/ManualModesVerification.md` MV-MODES-13/14/15).

- `0fbfdf5` #090.1 — `ProcessorSpec` schema: `descriptorID: String?` on `.transcriber` / `.streamingTranscriber`, `transcriberDescriptorID: String?` on `.diarizedTurns`. Codable round-trip via `encodeIfPresent` / `decodeIfPresent` so pre-#090 documents stay valid.
- `3cb4f4e` #090.2 — Validator: pinned specs bypass `availableKinds` rule and validate against `registeredDescriptors` instead. New `pinnedDescriptorNotRegistered` / `pinnedDescriptorKindMismatch` error cases. Validator + registry signatures gain a `registeredDescriptors[Provider]` param defaulted to the catalog so existing tests/callers compile unchanged.
- `54312b9` #090.3 — `RecipeBuilder.resolveDescriptor(for:pinnedID:)` honors the pin at session-start binding. Defensive `RecipeBuildError` cases mirror the validator's.
- `e82efea` #090.4 — Mutator pin support: `withVoiceModelPin` covers all three transcriber-bearing case shapes including `.diarizedTurns` ASR leg. `withRealtime` clears pin (kind change); `withDiarization` carries pin through (kind preserved). `ModeDetailViewModel.voiceModelPinID` getter + `setVoiceModelPin` setter.
- `89b05ba` #090.5 — Modes editor `voiceModelCard` becomes a SwiftUI Menu picker. Filters via `enabledModels(kind:)`. Caption + button-label handle three states (unpinned, pinned-known, pinned-unknown).
- `c03f310` #090.6 — Selectors filter invalid modes: menu-bar mode submenu hides modes that fail validation. Shared `ActiveModelService.availableKinds()`. Three manual-verification entries MV-MODES-13/14/15.
- `663b7e9` #090.7 — MV doc fix: invalid-pin chip is orange (validation warning), not red.
- `d6898d1` #090.8 — Per-mode hotkey table filters invalid modes (selector-filter parity with the menu-bar work in .6). Shared `AppComposition.currentlyValidCustomModes(among:)`.
- `f8f3961` #090.8 fix-up (codex) — wiring robustness: `startPerModeHotkeyObservation` was assuming `makeHotkeyMonitorWithPerModeWiring` had already installed the activation callback; on a fresh DMG that assumption broke and per-mode chords did nothing. Refactored into reusable `configurePerModeHotkeys` / `observePerModeHotkeys` helpers that re-install the callback before subscribing the stream. Two new tests synthesize an `NSEvent.keyDown` and assert the registry's `currentMode` flips. **Load-bearing** — without this, per-mode hotkeys silently fail post-build despite #090.8's filter being correct.
- `addeeae` (#089 follow-up) — back button on `ModeDetailView` toolbar (macOS NavigationStack doesn't auto-render). Caught during #090 dogfood.
- `e486f5b` (data fix) — `BuiltInModelCatalog.speakerDiarization.requiredRelativePaths` matches FluidAudio's offline diarizer artifacts (was inheriting the *online* diarizer's filenames). Caused `isDownloaded` to return false post-download → AI Models showed Download on a downloaded model + Modes rejected diarized recipes. Surfaced during #090 dogfood; not a #090 regression.

**Scope decisions adjudicated during the session**:
- Diarizer pin: **dropped**. Codex flagged that hidden state for a single-descriptor catalog creates a bug magnet. The `.diarizedTurns` case got `transcriberDescriptorID` only (the ASR leg); diarizer-leg pinning is deferred until a second diarization descriptor enters the catalog.
- Language hint: **carved out to #091**. Qwen3 memory re-validation post-`10a81f0` is the prerequisite; Parakeet language-hint blocked on upstream FluidAudio. Neither was in scope for #090.
- Per-mode hotkey filter: invalid modes are filtered out *before* registration via `AppComposition.currentlyValidCustomModes(among:)` → `monitor.updatePerModeHotkeys(...)`. Invalid modes never reach `GlobalHotkeyMonitor.perModeHotkeys`, so they cannot fire.

**Architectural note**: L23 (`ProcessorSpec` references `ModelKind` only, never `descriptor.id`) was first-pass and got rewritten as part of this work. The lock test `testProcessorSpecReferencesKindNotDescriptorID` was replaced with positive-form round-trip tests.

**Investigation artefacts**: `plans/investigations/2026-04-29-090-descriptor-pinning-claude.md` (pre-spin investigation) + `plans/investigations/2026-04-29-090-descriptor-pinning-codex.md` (codex review).

**Legacy:** session-generated 2026-04-28 from #089 grilling — language picker was originally V1 of #089. Pinning + language deferred per codex feasibility split, then split again into #090 (pinning, shipped) + #091 (language hint, deferred).

---

### #028 — Central KeyEventRouter consolidation (5a-v2)

`refactor` · `P1` · `done` · `area: hotkey`
*Updated 2026-05-01*

`KeyEventRouter` (in `Sources/PersonalScribeAppKit/Hotkeys/`) now owns the single `HotkeyEventTap` (CGEvent) + local NSEvent monitor + global NSEvent monitor that all hotkey consumers register against. Subscribers register deciders/observers via `register{Local,Global}Decider(_:position:)` / `registerGlobalObserver(_:)` and receive RAII `KeyEventRouterToken`s — dropping the token auto-unregisters via Task-dispatched MainActor cleanup. Dispatch is in registration order; `position: .first` lets transient subscribers (HotkeyRecorder) take priority over already-registered consumers.

**Shipped 2026-04-29**, 5 commits `dd9c185..03f4258` cherry-picked from `phase-3-028-key-event-router`. 1094 tests pass, 0 failures, 1 skipped.

- `dd9c185` #028.A — `KeyEventRouter` type + `KeyEventRouterToken` RAII + 8 unit tests covering registration order, swallow short-circuit, position-first, channel isolation, lifecycle.
- `5f4a825` #028.B — shared `AppComposition.keyEventRouter` static (started in `makeStartupCoordinator`'s `startHotkeyMonitor` closure, never stopped) + `EscapeKeyMonitor` migration. Drops `EscapeKeyMonitor`'s NSEvent install/uninstall typealiases; `start()`/`stop()` now register/drop tokens. `handle(event:)` migrated NSEvent → HotkeyEvent.
- `64ee425` #028.C — `GlobalHotkeyMonitor` migrates: drops `eventTap: HotkeyEventTap?`, `localMonitor: Any?`, `EventTapFactory`, `NSEventBox`. `start()` registers two deciders (local + global) on the router, both running the same gesture-machine entry. `router.isTapActive` surfaces Input-Monitoring-denied through the existing `handleMonitorInstallFailure` path. Local NSEvent decider stays usable when CG tap fails (small partial-recovery improvement vs. pre-#028 all-or-nothing).
- `e12df3e` #028.D — `HotkeyRecorder` SwiftUI shim migrates with `position: .first` for modal takeover; `HotkeyEvent` gains optional `charactersIgnoringModifiers` / `characters` fields (NSEvent path populates, CG path leaves nil) so the recorder can still render chord text from the same router channel.
- `03f4258` #028.E — fix-up: lift `KeyEventRouter` / `HotkeyEvent` / `HotkeyEventTap` / `CGHotkeyEventTapInstaller` / token / typealiases to `public` (Swift access-control cascade for `AppComposition.keyEventRouter`'s `public` declaration); guard `nsEvent.characters` reads against `.flagsChanged` events (NSEvent throws there); rearrange two trailing-closure call sites that violated positional-args-first ordering.
- `d6bddc7` #028 follow-up (2026-04-30) — menu bar's hardcoded `⌥⌥` "Start Recording" label flipped to live global hotkey; per-mode hotkey display added in the Mode submenu (parent + each child row).

**Foundation** that landed earlier (pre-#028): `HotkeyEventTap` (5a-v1) was already extracted as a DI'd CGEventTap wrapper. Its doc-comment named #028 as the eventual consumer. Made the migration low-risk.

**Depends on:** #001 (shipped, in `BACKLOG_ARCHIVE.md`)
**Legacy:** `ui-dogfood-bugs-2026-04-21.md` #19

---

## From `REBUILD_BACKLOG.md` (post-reset rebuild, 19 closed)

**Context:** Trunk was hard-reset to `b6699b2` on 2026-05-20 to escape a Parakeet streaming regression introduced by the VAD-boundary architecture (`9d1945b` + descendants). Bisect concluded the architecture itself was broken, not any single commit. Pre-reset trunk (44 commits) preserved on `origin/trunk` and via tag `bookmark-before-reset-2026-05-20`. Local trunk rebuilt by re-doing 7 feature buckets from scratch with clean commits + TDD. Backlog drained 2026-05-25 with bucket #6 (WhisperKit streaming). All buckets landed; local trunk unpushed.

| # | Feature | Commit | How |
|---|---|---|---|
| 0a | Diagnostics infra: log spam dedupe, log retention (14d default), on-demand diagnostics window, session lifecycle logs (`session_started_intent`/`_bound`/`streaming_session_started`) | `63bdc58` | hermes (req-0042) |
| 0b | CancellationError noise fix: `TranscriptRepository` 5 read methods stop logging Swift.CancellationError as failures | `cf4d184` | atlas direct |
| 0c | Graceful whisper.cpp adapter shutdown before `NSApplication.terminate` (fixes ggml_metal_rsets_free quit crash) | `1fcb5a1` | hermes (req-0043) |
| 0d | Fast-exit after graceful shutdown (skip whisper.cpp C++ atexit crash) | `36194c1` | hermes (req-0045) |
| 0e | Route all quit paths through fast-exit handler (NSApplicationDelegateAdaptor; covers status-item Quit + Cmd+Q + Cmd+Q-while-modal) | `de40fae` | hermes (req-0047) |
| 0f | Fix NSApplicationDelegateAdaptor crash-on-launch (override init() for FastExitApplicationTerminationDelegate) | `20058f2` | atlas direct |
| obs | Pipeline observability — 8 lifecycle logs (streaming input forwarded, adapter summary, orchestrator summary, stop resolution, stream card state, batch processing started/result, diarized processor summary) | `b465aea` | hermes (req-0046) |
| qwen+gates | Fix stale qwen3 hint test + add `AGENTS.md` delivery discipline (full-suite gate before DONE, launch-verification gate, canonical DONE format) | `f58cfe6` | atlas direct |
| debug-sink | Split debug.log sink + 3-day retention separate from errors/diagnostics 14-day retention | `f3ca7e1` | hermes (req-0049) |
| 1a | Mode-editor picker labels: drop Force/Live prefixes (`ParameterPickerView`, `SensitivityParameterPickerView`) | `cb99c59` | atlas direct |
| 1b+2+3 | Bundled: Whisper adapter filter (default `.both`) + per-mode language hint #091 + idle resource release for whispercpp/VAD lifecycles | `3bfaccb` | hermes (req-0048) |
| idle-all | Enforce `releaseIdleResources()` at protocol (drop default no-op) + add real implementations for Parakeet streaming/batch + Qwen3 + WhisperKit + diarizer + `adapter_idle_release` observability log | `1c23cfa` | hermes (req-0050) |
| logs-ui | Advanced settings: buttons to open errors.log / diagnostics.log / debug.log (falls back to logs/ dir when file not yet written) | `65011c8` | atlas direct |
| 4 | Audio recording persistence #069 Stage A (8 sub-features: DB relocation, v6 audio_filename column, RecordingFileWriter, pref-gated persist, cascade delete, Recordings UI card, RecordingRetentionSweeper, MV docs) | `2288e8b` | hermes (req-0044) |
| 5 | Offline file transcription #094 Stage A (FileSourceAudioStream, OfflineTranscriptionCoordinator, OfflineTranscriptionTab, menu-bar Retranscribe last recording, Transcriptions row Re-transcribe icon with press feedback + busy state, ToastBroadcaster, per-source dedup, list refresh on transcript-commit). 10x-engineer + pool-codex-1 reviews clean. | `bef41f7` | hermes (req-0051) |
| 7 | Whisper.cpp streaming adapter #099 (initial: `.whisperCppStreaming` engine + 3 paired catalog descriptors + tracker + VAD-as-EoU + merged-prefix dedup; +31 tests). **Partially reverted by #100** which consolidated to one descriptor + merged adapter. Streaming-side logic preserved in the merged actor. | `0c74b4d` | hermes (req-0054) |
| 8 | Engine capabilities + unified WhisperCpp adapter #100 — `TranscriptionEngine.capabilities: Set<ModelKind>`, one descriptor per artifact, ONE merged `WhisperCppAdapter` actor conforming to `Transcriber` + `StreamingTranscriber`, per-section `setActive(_:forKind:)`, `RecipeBuilder.buildStreamingSecondPassTranscriber` force-rule for `.whisperCpp`. Locked the shared-adapter design pattern. | `bc27776` | hermes |
| 9 | Live cursor EoU paste gated off for whisper.cpp streaming. `RecipeBuilder` forces `liveCursorEnabled=false` when streaming engine is `.whisperCpp` (CGEventPost is fire-and-forget; tracker produces duplicate EoU chunks from re-decode jitter and they paste irrevocably). UI surfaces the gate in Settings → General + Mode detail with disabled toggle + tooltip. Live card visualization + stop-time second-pass paste unaffected. | `11c0f99` | atlas direct |
| 6 | WhisperKit streaming adapter #101. Extended `TranscriptionEngine.whisperKit.capabilities = [.asr, .streamingASR]`; new `WhisperKitStreamingLedger` (confirmed-delta-only `.endOfUtterance` + unconfirmed-tail `.partial`); new `BufferFedWhisperKitAudioProcessor` (drives WhisperKit's `AudioStreamTranscriber` from our `PCMBuffer` stream); merged `WhisperKitAdapter` actor (renamed from `WhisperKitTranscriberAdapter`) conforming to both `Transcriber` + `StreamingTranscriber`; `ModelBoundProcessorProvider.whisperKit` factory wires same adapter to both batch + streaming slots; `RecipeBuilder` second-pass force-rule extends to `.whisperKit`. Live cursor stays user-controllable for WhisperKit (whisper.cpp gate does NOT extend — WhisperKit's internal `lastConfirmedSegmentEndSeconds` clipping prevents the duplicate-lane bug class). Codex audit (req-0069) corrected the original brief's "watermark = EoU" framing. +17 tests. | `dd100ee` + `322a4da` | hermes (req-0071) |

### Permanently deferred — DO NOT rebuild

| Feature | Why |
|---|---|
| VAD-boundary Parakeet rewrite (`9d1945b` + `c167155` + `497a4cf` + `9eba15e`) | Known bad — caused the streaming regression that prompted the reset. Re-design required if revisited. |

### Recovery anchors

- Tag `bookmark-before-reset-2026-05-20` (on origin) — pre-reset broken trunk, 44 commits ahead of `b6699b2`. Cherry-pick source for any reference commits.
- `origin/trunk` still has the old 44-commit history until force-pushed. Local trunk is canonical.

Active follow-ups split off as tickets: **#104** (whisper.cpp dedup tracker — deferred), **#105** (WhisperKit streaming dogfood verification), **#106** (delete `AppEntryPointTests.testPersonalScribeAppMainBuildsSceneModelFromComposition` skip), **#107** (memory idle-release note — archived below). They were filed as #039–#042 in the stale `plans/BACKLOG.md` and renumbered 2026-10-02.

---

## Archived 2026-10-02: 16 tickets closed (shipped audit + stale-backlog merge)

Closing evidence is on each ticket's `**Closed:**` line where the audit added one; #027 and #033 were already marked done.

### #018 — Clipboard clobber timing (configurable paste-restore delay)

`feature` · `P3` · `done` · `phase: 3` · `area: output, settings`
*Updated 2026-10-02*

**Closed:** `21ed9cd`, `a8f4f4f`, `6b9fa0c` — Settings exposes the restore-delay slider, `ClipboardRestoreDelay` persists it, and `ClipboardBatchOutput` reads it for each delivery.

Default 0.5s. Surface in Settings → Advanced.

**Legacy:** `PLAN_PHASES.md` Phase 3.H (UX-audit BUG-07)

---

### #027 — TranscriptEntry needs `modeId` + `trigger`

`refactor` · `P2` · `done` · `phase: 4` · `area: storage, session`
*Updated 2026-05-01*

Schema evolution to record which mode produced each transcript. Drives the row pill mockup (#032) and downstream filtering once Command Mode (#021) lands. Unparked 2026-04-30 — multiple modes now exist via the #089 editor, so `modeId` has information value even before #021. **Shipped 2026-05-01** in `156f43b` (squashed from `deb807f` + 2 follow-ups, pushed to trunk; 1126 tests / 1 skipped / 0 failures). Trigger field intentionally deferred per locked design.

**Codex follow-up baked into the squash:** `bindRecipeForNextSession(_:)` is mutated mid-flight by `SessionCoordinator` (eager pre-bind of the next session's recipe). The first cut read `boundRecipe?.recipeID` directly in `persist()` — a rebind landing during transcription would have rewritten the modeId. Same race on `runBoundProcessing`, `resolvedVadPreferencesForSession`, `currentBoundRecipe()`. Fix: introduce `activeSessionRecipe: BoundRecipe?` snapshotted at session start, retained through `.completed`, cleared on cancel/discard. Regression: `testCurrentBoundRecipeStaysSessionFrozenDespiteMidTranscriptionRebind`.

**Locked design (2026-04-30 grooming session):**

1. Add `preset: Preset` field to `WorkflowMode`. Codable additive — `decodeIfPresent` with `.dictation` fallback for pre-#027 documents. `Preset.materialize(name:)` sets it at creation time.
2. Change `WorkflowMode.id` format from `custom-{UUID}` to `{cleanName}-{suffix}` (suffix = short random / hash). One-time migration of existing `customModes` re-mints ids. `cleanName` = user-facing name at creation, stripped to id-safe chars.
3. Add `modeId: String` to `TranscriptEntry`. Captured at commit time from `registry.currentMode.id`.
4. #032 row-badge rendering paths:
   - **Live mode:** `customModes.first(where: { $0.id == modeId })?.preset.displayName` → "Notes" / "Meeting" / "Dictation" / "Streaming Dictation".
   - **Deleted mode:** `modeId.split(separator: "-").first.map(String.init)` → e.g. "Meeting" for `Meeting-7a3f1c`. Robust to backend file edits — dumb split, no schema dependency.
5. **No tombstone contract.** Mode deletion stays physical. The id-suffix scheme provides graceful fallback for orphaned transcript references — no GC strategy, no file growth, no naming-conflict tax.
6. **L-14 skip-gaps logic dissolves.** Any name reuse is fine because the suffix guarantees id uniqueness regardless of name collisions.

**Trigger field — decision deferred to unpark.** Brainstorm proposed `.hotkeyTap / .hotkeyHold / .menuBarClick / .pillClick`. May be dropped if no Command Mode use case requires it.

**Rejected approaches (2026-04-30 conversation):**
- `WorkflowMode` soft-delete / tombstone (legacy doc's original direction). File-growth + naming-conflict-on-reuse tax with no payoff once preset family is stored as a field.
- Encoding preset family in the id prefix (e.g. `notes-Meeting-{suffix}`). Field-based lookup on `WorkflowMode.preset` is more resilient — id parsing only used as fallback for orphaned references.
- Denormalising a `modeName` snapshot onto `TranscriptEntry`. Unnecessary once `WorkflowMode.preset` is a field and id encodes the name.

**Backward compatibility — per legacy doc + 2026-04-21 user direction:** existing `transcripts.jsonl` rows can be wiped (dogfood-era data) or backfilled to a sentinel. Pick at impl time.

**Depends on:** #026 (SQLite migration; sequencing decides whether the JSONL change is throwaway or first-schema-in-the-new-store), #021 (Command Mode — first consumer that drives distinct `modeId` values).

**Legacy:** `plans/_legacy/backlog/transcript-trigger-context.md` (2026-04-21 brainstorm; "Mode reference" section's tombstone direction superseded by the 2026-04-30 lock above).

---

### #033 — Streaming output transport decision

`refactor` · `P2` · `done` · `area: output, session`
*Updated 2026-05-02*

Live cursor stream transport for #056's streaming dictation. The live seam is `PipelineOutputSink.deliverPartial(_:)` (`Sources/PersonalScribeSession/Pipeline/Contracts/PipelineOutputSink.swift`); pre-#033 it had no production consumer.

**Decisions locked 2026-05-01** (Claude × Codex debate at [`plans/investigations/2026-05-01-033-transport-debate.md`](./plans/investigations/2026-05-01-033-transport-debate.md)):

| Sub-decision | Choice |
|---|---|
| Transport | clipboard chunk + synthetic `⌘V` |
| Undo grouping | per-EOU |
| Restore policy | save once at session start, restore once at session end (only when sink wrote a chunk) |
| Cursorless target | silent — last-EOU on clipboard, no UI affordance |
| Per-mode gate | paired — gate live partial on `liveCursorEnabled`; suppress stop-time `.frontmostPaste` when on |
| API shape | new `LiveCursorOutput` alongside `ClipboardBatchOutput` |
| Lifecycle hook | extend `PipelineOutputSink` with `endSession()` (default no-op) |

**Commits**
- `2a6e91f` — initial cohesive implementation (transport, paired gate, lifecycle hook, 19 tests).
- `46e2ed8` — Codex review follow-up: snapshot eagerly at session start (anchors locked Q1 wording, not first-chunk timing); `didWriteChunkThisSession` flag so non-streaming sessions don't over-restore; `endSession()` runs **before** `publish(.completed)` / `handleStageFailure` / short-exit publish (closes the ordering hole where menu-bar idle-transition observers could race the snapshot restore); `awaitLiveStreamingEventTaskShutdown` gains graceful-vs-immediate split (stop drains naturally, cancel cancels immediately); `waitForTaskCompletion` replaced with polling-loop + actor tracker (the previous `withTaskGroup` shape had a latent hang — `cancelAll()` doesn't unwind `await task.value` for `Task<Void, Never>`); 5 additional regression tests.
- `80f9bf0` — race + recipe-clear fix from dogfood errors at 2026-05-02 00:22:23.777Z (per `plans/investigations/2026-05-02-033-runtime-bugs-codex.md`). `startRecording()` gains `startRecordingInFlight` re-entry guard (preserves the prepare-before-publish invariant; closes the duplicate-`capture.start()` race that produced the `audioEngineFailure` errors). Catch-time `activeSessionRecipe = nil` removed from both `startRecording` and `startHoldRecording` — root cause of the downstream `runBoundProcessing → invalidState` chain (call B's catch nulled call A's recipe). `LiveCursorOutput.deliverPartial` now logs when `pasteShortcutPoster()` returns `false` (silent live-paint loss path Codex flagged). 1 new race regression test.

**Implementation surfaces:**
- `PipelineOutputSink.endSession()` — default no-op extension; called on success / cancel / error / short-exit / discard. Exists for session-scoped sinks like `LiveCursorOutput`.
- `LiveCursorOutput` (`Sources/PersonalScribeAppKit/Output/LiveCursorOutput.swift`) — captures pre-recording clipboard at `resetForNewSession` (session start); on `deliverPartial` writes the EOU chunk + posts `⌘V` (gated by AX trust + PID externality probe shared with `ClipboardBatchOutput`); on `endSession` restores the snapshot **only when at least one chunk wrote** this session (else discards — preserves user's mid-session clipboard for non-streaming sessions where the orchestrator still calls the sink lifecycle).
- `SessionPipelineOrchestrator.consumeLiveStreamingEvent` — capture-time `outputSink.deliverPartial(_:)` call gated on `bound.streamingBehavior?.liveCursorEnabled` (EOU events only, per #056 DESIGN's append-only contract).
- `RecipeBuilder` — paired Q4 gate filters `.frontmostPaste` from the bound recipe when `liveCursorEnabled == true` (avoids double-paste at session end).
- `SessionCoordinator` — accepts an injected `outputSink:` (falls back to no-op `CoordinatorPipelineOutputSink` for tests).
- `AppComposition` — constructs `LiveCursorOutput` and passes it to `SessionCoordinator`.

**Tests** (24 new across 4 files):
- `SessionPipelineOrchestratorTests`: live cursor delivery on EOU only (exact ordered equality, not `.contains`), suppression when disabled, ignores `.partial` events, `endSession` fires on each of {completed, shortExit, cancel, error}, `endSession` runs before `publish(.completed)`.
- `MenuBarSceneModelTests`: end-to-end ordering — menu-bar `deliverBatch` waits for pipeline `endSession` to complete.
- `RecipeBuilderTests`: `.frontmostPaste` filtered when live cursor on; preserved when off.
- `LiveCursorOutputTests`: writes chunk + posts paste, overwrites prior chunk, skips paste when AX untrusted or focus is in self, ignores blank text, `endSession` restores when chunk wrote, `endSession` discards (preserves mid-session clipboard) when no chunk wrote, `resetForNewSession` captures session-start snapshot before first chunk arrives.

Full suite at close: **1190 tests / 1 skipped / 0 failures** (post-`80f9bf0`).

**Known stale UI to clean up before next dogfood**
- `Sources/PersonalScribeAppKit/UnifiedWindow/Tabs/Modes/ModeDetailView.swift:130` and `Sources/PersonalScribeAppKit/Settings/GeneralTab.swift:341` still ship the caption *"Saved now for streaming recipes. Live cursor transport is not active in this build."* That text was added under #056 when transport was pending #033; now stale. Risk: users won't enable the toggle thinking it's a no-op. One-line removal in each file (or rewrite to reflect actual gating: AX trust + active streaming-ASR model + `liveCursorEnabled`).

**Out of scope (filed if dogfood demands):**
- Cumulative-during-cursorless clipboard (deliberately last-EOU only — second-pass authoritative final at session end is the safety net).
- ResponseCard "click into a text field" notice during cursorless period.
- Hybrid transport (CGEvent for short chunks, paste for long).

**Runtime verification:** in progress 2026-05-02 on the user's other laptop. First dogfood pass surfaced two errors (race + invalidState chain) — fixed in `80f9bf0`. EOU silent-paint inconsistency observed across tests 1-4: per Codex audit the cause is **EOU-only delivery + stop-before-EOU emission** (not a CGEvent paste race — app-side serialization is sound); `.finalized` event at stream-end intentionally doesn't backfill, so short utterances or VAD-pre-empted sessions paste nothing live. Decision pending: ship `.finalized`-backfill (Option B from the debate file) so single-utterance recordings paste at session end, or accept the locked "EOU chunks only" semantics. Reopen ticket if regression observed after rebuild on `80f9bf0`+.

**Legacy:** `backlog/streaming-output-delivery-mechanism.md` + `backlog/pipeline-streaming-defer.md` *(merged — same decision from two layer seats)*

---

### #034 — Waveform decay tuning

`feature` · `P3` · `done` · `area: pill`
*Updated 2026-10-02*

**Closed:** `2cd05d5`, `0c66f67` — `WaveformDecayMode.animated` linearly coasts the last level to zero over 0.5 seconds, and the recording pill renders `SineWaveView` with animated decay.

Tune falloff on the pill waveform so bars don't snap to zero.

**Legacy:** `ui-dogfood-bugs-2026-04-21.md` #10

---

### #091 — Per-mode language hint

`refactor` · `P2` · `done` · `area: transcription, models, modes, recipes`
*Updated 2026-10-02 (Filed 2026-04-29)*

**Closed:** `cbdd9a6` — `WorkflowMode` stores the hint, the mode editor filters choices through each descriptor's `supportedLanguages`, validation rejects invalid combinations, and the orchestrator passes the resolved hint to batch and diarized transcription.

When a pinned descriptor is multilingual, the user picks a target language for that mode. E.g. a "Japanese meeting" mode pinned to Qwen3 with `language: "ja"`.

**Why deferred from #090**: two prerequisites that #090 couldn't satisfy.

1. **Qwen3 re-enablement**. Qwen3 is `isEnabled: false` in `BuiltInModelCatalog` today (was a memory hog pre-#078). Post-#078 eviction fix (`10a81f0`) may have addressed it — needs re-validation on the Air with the released DMG. Until Qwen3 is re-enabled, the language picker has no consumer (Parakeet doesn't accept hints).
2. **Parakeet upstream blocker**. Parakeet's "25 EU languages" is a model-internal capability with no FluidAudio API to control target language at runtime. File a FluidAudio issue requesting per-call language hint for Parakeet TDT batch + streaming. Until that lands, Parakeet rows hide the language picker even though the model card claims multilingual.

**Scope**:
- Add `language: String?` to `.transcriber` / `.streamingTranscriber` / `.diarizedTurns` (or wrap in a `TranscriptionOptions` struct alongside `descriptorID`).
- Add `supportedLanguages: [String]?` to `ModelDescriptor`. nil = monolingual; otherwise structured language list (replaces freeform `worksWith` for picker logic, keeps `worksWith` for human copy).
- `WorkflowModeValidator`: validate language-present-on-supported-processor + language-supported-by-pinned-descriptor.
- `RecipeBuilder` → `BoundRecipe` → `Transcriber.transcribe(_:options:)` → adapters: thread the language through.
- `FluidAudioQwenTranscriberAdapter`: plumb language to `Qwen3AsrManager.transcribe(audioSamples:language:)`.
- Re-enable Qwen3 in `BuiltInModelCatalog` after memory re-validation.
- Modes editor: add a "Language" row that appears only when the selected descriptor has `supportedLanguages != nil`. Carries through to the `WorkflowMode` recipe.
- Reconcile language-list inconsistencies: codex flagged 16-vs-30 for Qwen, 24-vs-25 for Parakeet. File upstream issue or pin a canonical list with citations.

**Future-relevant**: when Whisper.cpp (or any other multilingual engine) lands, this seam already exists.

**Effort estimate** (carry-over from #090's codex breakdown):
- Descriptor metadata + mapping tables + validator wiring: 0.25-0.5d
- Recipe schema + Codable fallout + orchestrator/diarized-turn-processor plumbing: 0.5-0.75d
- Qwen adapter + live-manager + validation: 0.25-0.5d
- Modes editor integration: 0.25d
- Total: M (~1-1.5d) for "Qwen-only" scope; L (>1.5d) if waiting on upstream Parakeet.

**Depends on**: #090 (descriptor pinning, shipped). Qwen3 memory re-validation independent — schedule a 30-minute dogfood pass to confirm or deny the eviction fix's effect on Qwen.

**Evidence**: `plans/investigations/2026-04-28-multilang-feasibility-codex.md`.

**Legacy:** carved out of original #090 entry on 2026-04-29 when the descriptor-pinning slice shipped without language plumbing.

---

### #095 — Extend ASR catalog beyond Parakeet+Qwen

`feature` · `P2` · `done` · `area: transcription, models, catalog, multilingual`
*Updated 2026-10-02 (Filed 2026-04-30)*

**Closed:** `f6bb93c`, `0f4bb97`, `32ddfd4` — the catalog contains multiple multilingual WhisperKit descriptors, `ModelBoundProcessorProvider` routes them to the unified `WhisperKitAdapter`, and the adapter supports batch and streaming transcription.

Today the catalog ships English-only ASR (Parakeet TDT 0.6B v2/v3 + TDT-CTC 110M, plus Parakeet EOU streaming) and a single multilingual option (Qwen3 ASR, currently `isEnabled: false` per #091). Multilingual users have no working option. The English options are all NVIDIA Parakeet variants — same model family, no diversity in architecture or training data.

This ticket tracks adding an additional ASR family beyond what FluidAudio supports, starting with Whisper.

**No Tier 1 candidates exist today.** The only English-only Parakeet variant FluidAudio's `Repo` enum knows about that we haven't registered — `parakeet-ctc-0.6b-coreml` — is wired only into `CtcKeywordSpotter` (custom-vocabulary keyword detection), not the general `AsrManager`. Registering it as a transcriber descriptor would download the bytes but fail at session start because `AsrModelVersion` has no `ctc06b` case. Parakeet 1.1B has no CoreML conversion. Japanese/Chinese language-pinned variants are intentionally excluded from this scope (covered under per-language UX in #091).

**Tier 2 — Whisper via WhisperKit** *(the actual scope of this ticket)*

WhisperKit ([github.com/argmaxinc/WhisperKit](https://github.com/argmaxinc/WhisperKit)) is a pure-Swift Whisper runtime built on CoreML. Same author publishes pre-converted CoreML model bundles on HuggingFace (`argmaxinc/whisperkit-coreml`). Multilingual (~99 languages), gold-standard ASR accuracy, ANE-accelerated.

Why WhisperKit specifically over whisper.cpp:
- Pure Swift — no C++ bridging, no `module.modulemap` header juggling, less cross-platform glue.
- Idiomatic async/await + Combine API matches our existing adapter shape (`Transcriber` protocol from #078).
- Designed for Apple platforms; ANE acceleration on by default.
- whisper.cpp is more mature and cross-platform but Ninimma is macOS-only — the cross-platform value doesn't apply.

**Distil-Whisper note**: distilled smaller/faster Whisper variants from HuggingFace (`distil-large-v3`, `distil-medium`, `distil-small`). Loaded by the same WhisperKit runtime — not a separate runtime decision. If we want a "fast Whisper" tier alongside the accurate one, we ship a distil-* model bundle in addition to the standard one. Sub-decision under this ticket, not a separate ticket.

**Scope**:

1. **New Swift package dependency** — `argmaxinc/WhisperKit` in `Package.swift`. Pin a release (latest stable at filing time).
2. **New `TranscriptionEngine` case** — `.whisper` (or `.whisperKit` if we want to keep engine cases vendor-bound). Single case covers all model sizes; size differentiation lives in the descriptor `id` + display metadata.
3. **New `WhisperKitTranscriberAdapter`** — conforms to `Transcriber`. Mirrors `FluidAudioParakeetTranscriberAdapter`'s shape: `prepare()` loads the CoreML bundle via WhisperKit, `transcribe(_:)` runs inference, `modelDownloadProgress()` bridges WhisperKit's progress to our existing `ModelDownloadProgress` stream.
4. **Model descriptors** (start with one or two; expand on demand):
   - `whisper-large-v3-turbo` — accuracy/speed sweet spot. Most users.
   - `whisper-large-v3` — slowest, highest accuracy. Optional second slot for power users.
   - Optional `distil-large-v3` — fast English-focused tier. Defer until v2 if dogfooding shows demand.
5. **AI Models tab integration** — the tab iterates over `BuiltInModelCatalog.registeredModels`, so new entries surface automatically. Validate per-row metadata (size, WER, license) renders correctly.
6. **`worksWith` / `supportedLanguages`** — Whisper-large-v3 supports ~99 languages. Match against the schema decided in #091.
7. **`requiredRelativePaths`** — WhisperKit's CoreML bundle has its own folder layout (encoder + decoder + tokenizer); confirm against `argmaxinc/whisperkit-coreml` HF tree at conversion time.
8. **Tests** — `WhisperKitTranscriberAdapterTests` covering prepare/transcribe/progress flow against a stub WhisperKit; integration smoke test against a fixture audio if WhisperKit's API permits in-memory model injection.

**Effort estimate**:
- Package dependency + engine case + descriptor: 0.25d
- Adapter (load + transcribe + progress bridge): 0.5–1d (depends on WhisperKit's internals; first integration always overruns)
- Tests + fixtures: 0.25d
- AI Models tab metadata sourcing (HF tree fetch, license, WER, RTFx): 0.25d
- **Total**: M (~1.25–2d) for one model size; +0.25d per additional descriptor.

**Depends on**: nothing blocking. Plays well with #091 (per-mode language hint) — Whisper's multilingual nature is the ideal consumer of the language picker once #091 lands.

**Unblocks**: multilingual transcription for non-English users. Optional fallback when Parakeet underperforms on a recording's domain (medical, legal, accented speech).

---

## Tier 3 — reference notes (future / out-of-scope for this ticket)

Models considered but not in immediate scope. Left here so future readers don't re-research the same ground.

- **NVIDIA Canary** (`canary-1b`, `canary-180m-flash`) — multilingual ASR (en/de/es/fr) plus speech translation. Strong benchmarks. NeMo checkpoint format only; no CoreML conversion published. Adding requires NeMo→CoreML conversion pipeline (significant) or waiting for someone (FluidInference?) to publish.
- **NVIDIA Parakeet 1.1B variants** (`parakeet-tdt-1.1b`, `parakeet-rnnt-1.1b`, `parakeet-ctc-1.1b`) — bigger sibling of the 0.6B. Same conversion blocker as Canary: NeMo only, no CoreML.
- **Pure CTC 0.6B** (`FluidInference/parakeet-ctc-0.6b-coreml`) — CoreML exists but FluidAudio's `AsrModelVersion` enum has no `ctc06b` case, so `AsrManager` won't load it as a transcriber. Currently used internally by `CtcKeywordSpotter` only. Unblocks if FluidAudio adds the case OR if we write our own inference pipeline on top of the loaded models.
- **IBM Granite Speech 3.3** — open weights, multilingual. CoreML ecosystem immature. Wait-and-see.
- **Microsoft Phi-4 multimodal** — speech-aware multimodal model. New (early 2025); CoreML conversions immature.
- **Meta SeamlessM4T** — speech-to-text + translation in one model. Heavy. Better fit if Ninimma ever adds a translation feature; not pure ASR.
- **whisper.cpp** — alternative Whisper runtime. More mature than WhisperKit, but C++ bridging + cross-platform features that don't apply to a macOS-only app. Defer unless WhisperKit hits a wall.

**Legacy:** none — net-new.

---

### #096 — Diagnostics system consolidation

`refactor` · `P2` · `done` · `area: diagnostics, observability, errors, settings`
*Updated 2026-10-02 (Filed 2026-04-30)*

**Closed:** `56a8b95`, `53ebbbf`, `5df8635`, `81f4b1d` — `DiagnosticsReporter` owns the structured event model and sinks, the old session reporter is gone, Advanced settings controls capture and retention, and the filterable live diagnostics window is wired through app composition.

Today's diagnostics is split across two adjacent mechanisms:

- `Sources/PersonalScribeCore/Logger.swift` — `PersonalScribeLogger` wraps `os.Logger` for `debug / info / error` (~100 call sites in Sources/).
- `Sources/PersonalScribeCore/SessionErrorReporter.swift` — structured session failures → `logs/errors.log` + `ReportedError` for the response-card path (added in `30381cf` / #092.5).

That split is workable for the immediate error-display fix but is the wrong long-term shape — there's one event-emission concept being expressed twice. This ticket consolidates both into a single `DiagnosticsReporter` with one shared event model, optional `userFacing` payload that gates UI surfacing without coupling logging to UI, and adds Advanced-settings controls for verbose disk capture + a live diagnostics overlay panel.

**Locked architectural decisions** (see design doc):

- D1: One diagnostics system, one event model. No "logger vs reporter" split.
- D2: `userFacing` is optional metadata on the event. **Not** a parallel `errorWithUserReport(...)` API.
- D3: Diagnostics layer never imports AppKit. Session/UI layer converts `userFacing` payload to `SessionSnapshot.reportedError`. ResponseCard remains one consumer of that snapshot field.
- D4: Error-level events always persist to `logs/errors.log` regardless of verbosity setting. Settings widen capture, never disable error logging.
- D5: Advanced settings own `Diagnostic Logging` (`Errors Only` default / `Verbose`) + `Show Live Diagnostics Overlay` (off; only available when Verbose).
- D6: `Diagnostics*` types live in `PersonalScribeCore`. Live overlay UI lives in `PersonalScribeAppKit`, consumes the in-memory ring buffer through public Core API.
- D7: `DiagnosticsReporter` is constructed in `AppComposition` with sinks injected. Tests inject reporter with `InMemoryTestSink`. No `Diagnostics.shared` singleton.

**Sinks** (all behind one fan-out reporter):

- `OSLogSink` — replaces direct `PersonalScribeLogger` writes.
- `ErrorFileSink` — `logs/errors.log` (always-on).
- `VerboseFileSink` — `logs/diagnostics.log` (Verbose only). Errors NOT duplicated.
- `RingBufferSink` — bounded (~200 events), feeds the live overlay.
- `InMemoryTestSink` — unbounded + ordered; test-only, asserts emitted events.

**PII redaction** at sink boundary via `PIIRedactor`:

- Always-safe metadata keys: `level`, `category`, `mappedError`, `stage`, `mode`, `descriptorID`, `pipelineShape`, `errorType`.
- Always-redacted metadata keys: `transcript`, `path`, `deviceName`, `windowTitle`, `appName`, `audioFile`, `userMessage`. Value → `<redacted>`; key preserved for grep.
- Value-pattern: regex `/Users/[^/]+` → `/Users/<redacted>`.
- `underlyingError` rendered as `String(describing: type(of: error))` + case name; never `String(describing: error)`.

**Rollout** (Stage A–G; each stage leaves repo buildable):

- A. Core diagnostics primitives (event/level/sinks/reporter/PIIRedactor).
- B. Cut over `PersonalScribeLogger` — recommendation: retire after migration, mechanical rename of ~100 sites, delete `Logger.swift`. (Codex's plan currently keeps a permanent facade — pick before B starts.)
- C. Session failure path migrated to emit through `DiagnosticsReporter` with `userFacing: .sessionError(...)`.
- D. Non-session blind spots (`MenuBarSceneModel` auto-paste, `SessionCoordinator` persistence, orchestrator prewarm) emit via reporter; no `userFacing`.
- E. Advanced-settings UI: `DiagnosticLoggingMode` enum + `showLiveDiagnosticsOverlay` bool. AppComposition wires sinks based on mode.
- F. Live diagnostics overlay (`LiveDiagnosticsOverlayController/Presenter/View`) — separate floating panel, ResponseCard styling, persistent + scrollable + filterable + copy button. Read-only; no paste, no link actions.
- G. Cleanup + docs + manual verification runbook (`MV-DIAG-1..5`).

**Plans on disk** (read these first before implementation):

- `plans/diagnostics-system-design.md` — locked decisions D1–D7 + Q1–Q4 + PII section.
- `plans/diagnostics-system-implementation.md` — Stage A–G rollout, file lists, test expectations, exit criteria.
- `plans/diagnostics-system-review.md` — concrete edits Codex should fold into both docs before starting (PII section, two-file model, retire-vs-facade, DI wiring example).

**Effort estimate**: L (>1.5d) for full A–G; M (~1d) for Stage A alone.

**Depends on**: nothing blocking. #092.5 (`30381cf`) is the precondition that proves the snapshot-driven UI seam works; this ticket consolidates the diagnostics backend the response-card seam already depends on.

**Unblocks**: live debug overlay during dogfooding (currently no on-screen visibility into recent events); structured telemetry layer if ever needed; cleaner extension point for new categories without pollination across two systems.

**Legacy:** none — net-new. Picks up where #092.5 left off.

---

### #097 — Paste pipeline observability (summary-shape)

`infra` · `P2` · `done` · `area: paste, diagnostics, observability`
*Updated 2026-10-02*

**Closed:** `549772e` — `PasteSessionAccumulator` records live/final paste outcomes and renders one `paste_session_summary` at the session boundary without transcript content.

Stage A shipped. 10x-engineer review C1 (clipboard-only delivery was
recording `finalPasteSucceeded=true`) folded into the same commit:
`finalPasteSkipped` field now distinguishes clipboard-only delivery
from `⌘V` landing.

The paste pipeline has **zero structured logging today**. Symptom that surfaced this gap (2026-05-24 dogfood):

> "Live cursor pastes during streaming, but the final post-EoU output is not pasted at all. Can you confirm from logs?"

Atlas grepped `diagnostics.log` for `live_paste`, `paste_attempt`, `paste_succeeded`, `paste_failed`, `live_cursor`, `writeAndPaste`, `pasteText` — **all zero hits**. The user observation is plausible (terminal text was 39 chars post-EoU on the affected session, consistent with "first paste landed, final didn't"), but log-unverifiable. Every future paste-adjacent bug hits the same wall.

Add diagnostics so we can answer "did the paste land?" from logs alone. Follow `INSTRUMENTATION_PRINCIPLES.md`:
- Summary-at-boundary shape, not per-event (per-event would spam during live-cursor replace).
- Counts and shapes, not paste content (privacy + `principle #3`).
- Reuses precedent of `stream_card_state_changed` collapse → summary (`0771c07`) and `streaming_adapter_summary` / `streaming_orchestrator_summary` shapes.

**Locked logging shape:**

One summary log per paste session boundary (session end / pipeline teardown), carrying aggregate counts:

```
paste_session_summary — sessionID=<id>
  livePasteAttempts=<int> livePasteSucceeded=<int> livePasteFailed=<int>
  livePasteReplaceOps=<int> livePasteCumulativeCharsWritten=<int>
  finalPasteAttempted=<bool> finalPasteSucceeded=<bool> finalPasteCharsWritten=<int>
  finalPasteFailureReason=<enum?>
  targetAppPID=<pid?> targetAppBundleID=<bundle?>
  totalDurationMs=<int>
```

**Error-level logs (always-on, errors.log)**: paste failures that abort with no fallback. One log per failure, not per attempt:

```
paste_failed — stage=<live|final> reason=<noTargetCursor|pidProbeRejected|eventPostFailed|other> attemptedChars=<int>
```

**Explicitly out of scope:**
- Per-paste-event info logs (would spam ~1/sec during live replace — violates frequency budget #1).
- Logging paste content (violates principle #3).
- Per-keystroke / per-CGEventPost debug events (those belong in `debug.log` only, behind a Verbose toggle that #096 introduces).

**Scope:**
- Identify the paste-pipeline boundary that owns the session lifecycle (likely `LiveCursorWriter` or its caller in the pipeline orchestrator — grep for `CGEventPost` / `NSPasteboard.general.setString`).
- Thread a per-session accumulator through the paste path, emit the summary at teardown.
- Add `paste_failed` error-level log at the existing failure branches (no new failure detection — just instrument what's already a `return` / `throw` site).
- Document the events + frequency budget in `docs/INSTRUMENTATION_PRINCIPLES.md`.

**Tests:**
- Unit-test the accumulator's count math (`livePasteAttempts` increments on each attempt, `livePasteSucceeded` only on success, etc.).
- Integration-test that a paste pipeline mock fires the summary at teardown with the right counts.
- No test asserting the literal log string — test the accumulator's exposed `Summary` value.

**Depends on**: nothing. #096 (Diagnostics consolidation) would make the sink wiring cleaner but is not a blocker — current `PersonalScribeLogger.info(...)` is sufficient for Stage A.

**Unblocks**:
- Verifying / refuting the "final paste doesn't land after Parakeet EoU" bug surfaced 2026-05-24.
- Future paste-pipeline bug triage without re-instrumenting from scratch each time.
- Quantifying paste reliability (success rate, failure-reason histogram) before deciding whether an overlay-edit mode is needed as a workaround for live-paste fragility.

**Connected work — Parakeet EoU degraded-output bug (separate ticket TBD)**: the same session that surfaced this gap also showed Parakeet streaming going into a near-mute mode after one EoU fires (9 partials in 37.5s vs 88 partials in a comparable session without EoU). Paste observability is a prerequisite for diagnosing whether the EoU bug's "no final paste" symptom is upstream (no final text emitted) or downstream (text emitted but paste fails). File the Parakeet EoU ticket separately once we have logs to disambiguate.

**Legacy:** none — net-new.

---

### #098 — Streaming paste fixes (drop double-paste filter + chunk spacing + final-paste newline)

`bug` · `P2` · `done` · `area: paste, streaming, recipes`
*Updated 2026-10-02*

**Closed:** `f0e0238` — live-cursor recipes retain final paste, subsequent EOU chunks gain a leading space, and final batch paste gains a newline only after a live paste occurred.

Three coupled fixes shipped: (A) RecipeBuilder no longer filters
`.frontmostPaste` when liveCursor=true; (B) `LiveCursorOutput`
prepends a single space between EoU chunks; (C)
`ClipboardBatchOutput` prepends `"\n"` before the final paste when
`AppComposition.liveCursorOutput.lastSessionLivePasteAttempts > 0`
and `.frontmostPaste(enabled: true)`. Wiring uses a closure
parameter on `ClipboardBatchOutput` reading from a lifted
`AppComposition.liveCursorOutput` static.

Surfaced 2026-05-24 dogfood, confirmed via #097 logs:

1. **Streaming mode's auto-paste setting is silently filtered out.** When `streamingBehavior.liveCursorEnabled == true`, `RecipeBuilder.swift:48-52` drops the `.frontmostPaste` sink from the bound recipe under the rationale "live cursor already pastes per-EOU; stop-time would double-paste." But Parakeet streaming reality: live cursor only pastes EoU chunks (which fire sparsely or not at all per session), and the second-pass authoritative final is *different text* than what was live-pasted (different model, cleaner punctuation). User wants BOTH pasted and to choose which they keep — not one silently dropped.

2. **Live cursor chunks concatenate without spacing.** Consecutive `.endOfUtterance` chunks pasted via `LiveCursorOutput.deliverPartial(_:)` overwrite the clipboard with raw chunk text. When `Cmd+V` lands them sequentially the last word of chunk N runs into the first word of chunk N+1 (`"hello world" + "how are you"` → `"hello worldhow are you"`).

3. **No separator between live-pasted chunks and the final authoritative paste.** Once (1) is fixed and `.frontmostPaste` flows through, the final paste lands immediately after the last live-pasted chunk — same concatenation problem at a larger scale.

**Locked design (user decisions 2026-05-24):**

- **(A)** Drop the `RecipeBuilder.swift:48-52` filter entirely. Streaming mode's auto-paste setting drives `.frontmostPaste(enabled:)` like every other mode. If the user enables both `liveCursor` AND `autoPaste`, both fire — user picks which output they prefer.
- **(B)** `LiveCursorOutput.deliverPartial(_:)`: first chunk pastes unchanged. Subsequent chunks prepend a single space (`" \(chunk)"`) before writing to clipboard. Track "did we already paste a chunk this session?" via the existing `didWriteChunkThisSession` flag (already used for restore semantics) — when true, prepend space.
- **(C)** `ClipboardBatchOutput.deliverBatch(...)`: when live cursor actually pasted ≥1 chunk in the same session AND `.frontmostPaste(enabled: true)` is in the sinks, prepend `"\n"` to the text before clipboard write. Use #097's `livePasteAttempts > 0` signal as the "actually pasted" gate (avoids stray newline when zero EoU chunks fired in a short streaming session).

**Out of scope:**
- Per-mode separator picker (space vs newline vs custom). Single-space hard-coded for now; can revisit if dogfood shows it's wrong.
- Restructuring the orchestrator's sink ownership / dispatch. Minimal plumbing.
- Anything in `LiveCursorOutput` beyond the chunk separator.

**Scope:**
- `Sources/PersonalScribeSession/WorkflowMode/RecipeBuilder.swift:48-52`: remove the filter.
- `Sources/PersonalScribeAppKit/Output/LiveCursorOutput.swift`: chunk separator logic; reuse `didWriteChunkThisSession`.
- `Sources/PersonalScribeAppKit/Output/ClipboardBatchOutput.swift`: accept a `liveCursorDidPaste: Bool` signal (parameter on `deliverBatch` OR shared accessor on a session-context type), prepend `"\n"` when true + paste enabled.
- Plumbing: wherever `deliverBatch` is called by the orchestrator, pass through the live sink's `livePasteAttempts > 0` snapshot. Likely via a `PasteSessionContext` value type held by the orchestrator (small struct, not a refactor).

**Tests:**
- `RecipeBuilderTests`: expect 1-2 tests asserting the old filter behavior — update to assert `.frontmostPaste` survives when `liveCursorEnabled=true`.
- `LiveCursorOutputTests` (new): `testFirstChunkPastesUnchanged`, `testSecondChunkPrependsSpace`, `testResetForNewSessionResetsChunkCounter`.
- `ClipboardBatchOutputTests` (new): `testFinalPastePrependsNewlineWhenLiveCursorDidPaste`, `testFinalPasteDoesNotPrependNewlineWhenLiveCursorDidNotPaste`, `testFinalPasteDoesNotPrependNewlineWhenPasteDisabled`.

**Depends on**: #097 (#097's accumulator provides the `livePasteAttempts > 0` signal needed for (C)).

**Unblocks**: usable Parakeet streaming dictation — without #098, streaming-mode output is broken in two visible ways (no live paste of authoritative final, runtogether words).

**Legacy:** none — net-new bug fix.

---

### #100 — Engine capabilities + unified WhisperCpp adapter (collapse #099 split)

`refactor` · `P2` · `done` · `area: models, transcription, recipes, picker`
*Updated 2026-10-02*

**Closed:** `8570c4a` — `TranscriptionEngine.capabilities`, per-kind activation, and the single batch/streaming `WhisperCppAdapter` replace the split engine and duplicate adapter instances.

Shipped: capability-set on TranscriptionEngine, per-section
setActive(_:forKind:), merged WhisperCppAdapter (one actor, both
protocols, single context), force-second-pass for whisper.cpp
streaming. .whisperCppStreaming engine case + 3 streaming
descriptors from #099 dropped. 10x review folded in (C1+C2+C4).
No UserDefaults migration (whispercpp-streaming-* IDs never
released).

#099 shipped whisper.cpp streaming by adding a new `.whisperCppStreaming`
engine case + 3 paired ModelDescriptor entries that share `repoFolderName`
with their batch siblings. That choice (Option 1, mirroring pre-reset
`5a0df9e`) was driven by a kind-system constraint: `ActiveModelService.visibleModels(kind:)`
and `RecipeBuilder.resolveDescriptor` both filter by singular
`descriptor.engine.kind`, so a whisper.cpp model that's batch-AND-streaming
capable couldn't appear in both picker sections under a single descriptor.

The cost of #099's choice:
- 6 catalog rows for 3 underlying `.bin` files (user sees duplicate-looking
  picker entries)
- Two adapter instances per `.bin` when streaming + batch are both active
  (RAM doubles: ~200-600MB extra per session depending on model size)
- 3 descriptors to maintain per future whisper.cpp model addition

**Design (user-locked 2026-05-24):**

Replace singular `TranscriptionEngine.kind: ModelKind` with capability set
`TranscriptionEngine.capabilities: Set<ModelKind>`. `.whisperCpp.capabilities = [.asr, .streamingASR]`;
all other engines stay single-capability. Filter sites (`visibleModels(kind:)`,
`RecipeBuilder.resolveDescriptor` pinned-kind check, AIModelsTab section
filter) use `capabilities.contains(kind)` instead of `kind == kind`.

`ActiveModelService.setActive(_:)` fans out across all capabilities the
descriptor satisfies — picking whisper.cpp activates it as both
`activeModelIDs[.asr]` AND `activeModelIDs[.streamingASR]` in one call.
The user clicks "Make active" on a whisper.cpp row; it becomes the user's
whisper.cpp model for both jobs.

Merge `WhisperCppStreamingTranscriberAdapter` + `WhisperCppTranscriberAdapter`
into ONE `WhisperCppAdapter` actor conforming to both `Transcriber` AND
`StreamingTranscriber`. Single whisper.cpp context per descriptor; both
decode entry points operate on it. `ModelBoundProcessorProvider`'s `.whisperCpp`
factory returns one adapter instance, populated as both `transcriber:` AND
`streamingTranscriber:` in the `AdapterRecord`. `releaseIdleResources()`
contract honored at the actor level (one timer guarding the one context).

Drop:
- `TranscriptionEngine.whisperCppStreaming` case + Codable + kind mapping
- 3 catalog descriptors `whispercpp-streaming-tiny`, `whispercpp-streaming-small-q5_1`,
  `whispercpp-streaming-large-v3-turbo-q5_0`
- `ModelBoundProcessorProvider.AdapterRecord` factory case for `.whisperCppStreaming`
- `SessionCoordinator.whisperCppDescriptorsForApplicationTermination`'s
  `.streamingASR` union (now redundant — capability fan-out covers it)
- All tests asserting the split shape

**UserDefaults migration:**

Users who already saw the post-#099 picker may have activated
`whispercpp-streaming-small-q5_1` (the streaming descriptor). After this
ticket those IDs no longer exist. `ActiveModelService.init` reads stored
IDs from UserDefaults — if a stored ID looks like `whispercpp-streaming-*`,
strip the `-streaming` segment and rewrite to the surviving batch descriptor
ID (e.g. `whispercpp-streaming-small-q5_1` → `whispercpp-small-q5_1`).
One-shot migration; safe because the underlying `.bin` is identical.

**Concurrency note:**

Within a single session: streaming (during recording) and batch second-pass
(after recording stops) never overlap in time. One context, two sequential
consumers — no internal serialization needed.

Across sessions: if user starts session N+1 before session N's second-pass
batch decode finishes, both call sites on the same actor compete. Actor's
isolation serializes them — second-pass blocks streaming briefly OR
streaming blocks second-pass briefly. Either is acceptable for the rare
back-to-back case. Surface the trade-off in adapter logging
(`whispercpp_concurrent_access`) if it ever matters for diagnostics.

**Scope:**

- `Sources/PersonalScribeCore/Models/Selection/ModelDescriptor.swift` — `capabilities` field on TranscriptionEngine; remove `whisperCppStreaming` case
- `Sources/PersonalScribeCore/Models/Selection/TranscriptionEngine+Codable.swift` — remove streaming case
- `Sources/PersonalScribeCore/Models/Selection/TranscriptionEngine+Kind.swift` — replace `kind` property with `capabilities`
- `Sources/PersonalScribeCore/Models/Selection/BuiltInModelCatalog.swift` — drop 3 streaming descriptor entries + the `whisperCppStreamingDescriptor(pairedWith:)` helper
- `Sources/PersonalScribeSession/Models/Selection/ActiveModelService.swift` — `setActive(_:)` fans out to all capabilities; `visibleModels(kind:)` uses capabilities.contains
- `Sources/PersonalScribeSession/Models/Selection/ModelBoundProcessorProvider.swift` — `.whisperCpp` factory creates one merged adapter, populates both slots
- `Sources/PersonalScribeSession/WorkflowMode/RecipeBuilder.swift` — pinned-kind check uses capabilities.contains
- `Sources/PersonalScribeSession/SessionCoordinator.swift` — eviction filter drops streaming union (now redundant)
- `Sources/PersonalScribeTranscription/Adapters/WhisperCppAdapter.swift` — NEW merged actor (replaces both batch + streaming adapters)
- `Sources/PersonalScribeAppKit/Settings/AIModelsTab.swift` — section filter uses capabilities.contains
- `Sources/PersonalScribeAppKit/Settings/ActiveModelIDsMigration.swift` — NEW one-shot migration for stored whispercpp-streaming-* IDs

**Out of scope:**
- Expanding capabilities for other engines (whisperKit, parakeetTDT) — they could add `.streamingASR` later but that's per-engine work
- Per-mode whisper.cpp settings split between streaming and batch passes (currently both use the same defaults; future ticket if dogfood asks)
- Cross-process whisper.cpp context sharing

**Tests:**
- `TranscriptionEngineCapabilitiesTests` (NEW) — per-engine capability set
- `ActiveModelServiceTests` extended — setActive fans out across capabilities; visibleModels uses contains
- `BuiltInModelCatalogTests` — drop 3 streaming-descriptor assertions
- `ModelBoundProcessorProviderTests` — same descriptor resolves to both transcriber AND streamingTranscriber, same instance
- `WhisperCppAdapterTests` (NEW or renamed) — merged tests from former streaming + batch adapter tests
- `ActiveModelIDsMigrationTests` (NEW) — stored `whispercpp-streaming-*` ID gets rewritten on first read

**Depends on**: #099 (this is its partial revert + redesign).

**Unblocks**: future engines that grow multi-capability without further refactors; ~300-600MB RAM saved per whisper.cpp streaming session that also runs second-pass.

**Legacy:** partially reverts #099's catalog-split decision. Net delta: fewer files, cleaner kind taxonomy, less duplicated RAM.

---

### #107 — Memory idle-release verified (informational, no action)

`feature` · `P3` · `done` · `area: lifecycle`
*Updated 2026-05-25*

Idle release working as designed (req-0050, `1c23cfa`). Verified empirically 2026-05-24 night: batch session 60→300→90 MB (93% reclaim), streaming session 90→723→333 MB (62% reclaim). Streaming residual is dominated by Parakeet TDT 0.6B used as second-pass batch (~600 MB peak). If lower streaming residual is needed, switching active batch ASR from Parakeet TDT 0.6B to Whisper Small WhisperKit (216 MB) cuts peak by ~400 MB. Current setting intentional per quality preference.

**No action.** Keep as ticket so the empirical numbers don't get lost.

**Legacy:** `plans/BACKLOG.md` #042 (ID already used in `BACKLOG_ARCHIVE.md`; renumbered 2026-10-02)

---

### #105 — WhisperKit streaming dogfood verification

`feature` · `P2` · `done` · `stage: verify` · `area: transcription, streaming, dogfood`
*Updated 2026-10-02*

The WhisperKit streaming adapter (rebuild bucket 6, `dd100ee` + `322a4da`) landed. Source + tests green (1496/0/1) but no DMG-built dogfood exercise yet. Built app at `/Applications/Ninimma.app` is on `11c0f99` (one commit behind #101).

**Verification checklist:**
- Rebuild + sign + reinstall DMG.
- Switch active streaming model to a WhisperKit descriptor in AI Models tab.
- Run streaming dictation: confirm `.endOfUtterance` chunks paste cleanly via live cursor into focused app (confirmed-delta-only emission means no parallel-lane duplicates).
- Confirm live card updates with unconfirmed-tail `.partial` events during speech, then committed segments on confirmation.
- Run stop-time second pass: confirm force-rule reuses the same WhisperKit instance (no second download/load).
- Regression: switch back to Parakeet streaming and confirm it still works as before the #100 and WhisperKit-streaming catalog changes.
- Regression: switch back to whisper.cpp streaming and confirm the live-cursor gate still suppresses EoU paste.

**Reference:** plans/101_whisperkit_streaming/HERMES_BRIEF.md; CODEX_RESEARCH.md.

**Legacy:** `plans/BACKLOG.md` #040 (ID already used in `BACKLOG_ARCHIVE.md`; renumbered 2026-10-02)

**Closed:** 2026-10-02 — user ran WhisperKit streaming dictation in the installed app; the end-to-end benchmark (`StreamingSecondPassBenchmarkTests`) also ran WhisperKit live + second pass on real models.

---

### #106 — Delete `AppEntryPointTests.testPersonalScribeAppMainBuildsSceneModelFromComposition` skip

`refactor` · `P3` · `done` · `stage: impl` · `area: tests`
*Updated 2026-10-02*

Test skipped since 2026-04-20 because `@StateObject` lifetime isn't retained in unit-test context. `MenuBarFlowIntegrationTests.testRecordStopTranscribeIdleFlowPublishesLatestResult` already covers the composition end-to-end without depending on `@StateObject` lifetime, so the skipped test is redundant.

**Action:** delete the test (not unskip, not refactor). Full suite expected to drop from 1496 pass / 1 skip → 1495 pass / 0 skip.

**Legacy:** `plans/BACKLOG.md` #041 (ID already used in `BACKLOG_ARCHIVE.md`; renumbered 2026-10-02)

**Closed:** 2026-10-02 — `AppEntryPointTests.swift` deleted; `MenuBarFlowIntegrationTests.testRecordStopTranscribeIdleFlowPublishesLatestResult` covers the flow.

---

### #056 — Streaming dictation mode (StreamCard + EOU cursor stream + optional second pass)

`feature` · `P2` · `done` · `phase: 4` · `area: dictation, session`
*Updated 2026-10-02*

**Shipped so far:** `94fc079`, `dd41738`, `f5ec7cc`, `5deed46`, `9541643`, `2419927` — StreamCard, EOU cursor delivery, second-pass fallback, and session-lifecycle hardening are in the current pipeline; runtime verification remains open.

V1 remains a user-created custom mode / preset (not a built-in mode). English-only. Precondition for #057 (app-context rules).

**Design:** [`plans/056_streaming_dictation/DESIGN.md`](./plans/056_streaming_dictation/DESIGN.md)
**Implementation:** [`plans/056_streaming_dictation/IMPLEMENTATION.md`](./plans/056_streaming_dictation/IMPLEMENTATION.md)

**Locked design (2026-04-30):**
- Split surfaces:
  - `StreamCard` = live transcript only, controlled by the session pipeline.
  - existing `ResponseCard` = short operational/status messages only (`Finalizing…`, `Copied to clipboard`, `Clipboard restored`, transport fallback / errors).
- `StreamCard` shows the rolling session tail. Make it wider than the current ResponseCard, but keep it single-line. No editing.
- Live cursor streaming is a separate setting (global default + per-mode override). Cursor delivery is append-only and emits end-of-utterance chunks only.
- If live cursor streaming is on, there is never an extra stop-time cursor write.
- Second pass is optional (global default + per-mode override). When enabled, it is authoritative for history + clipboard only; it never rewrites external apps. If second pass fails, fall back to the streaming model's final text.
- If second pass is off, persist/copy the streaming model's own final text.
- Restore-clipboard in live mode restores the pre-recording clipboard snapshot.
- Existing final auto-paste path still applies only when live cursor streaming is off.

**Status (2026-05-02):** all 6 IMPLEMENTATION stages plus the post-implementation hardening commits have landed on trunk. Live cursor transport (#033) is wired through `LiveCursorOutput`. Code is complete; **runtime verification in progress on the user's other laptop**. Stale dogfood lines from earlier rounds removed — the prior body claimed "no live partial surface wired" which is no longer true post-`41c2024`/`51fb4a8`/`46e2ed8`.

**Scope notes:**
- `Streaming Dictation` is a custom-mode preset (#089 covers per-mode hotkeys / mode selection).
- StreamCard surface, second-pass authoritative final, and cursor-stream transport are all live.
- Shared audio spooling / temp-file capture is out of scope for #056 and should land as shared infrastructure for all modes (separate ticket if dogfood demands).

**Known stale UI** (slated for #033 cleanup, not blocking): `ModeDetailView.swift:130` + `GeneralTab.swift:341` still display *"Live cursor transport is not active in this build."* — pre-#033 wording.

**Depends on:** #033 (✅ done) — wired the live cursor transport.

**Legacy:** `plans/_legacy/BACKLOG_pre_migration.md` → "Streaming dictation mode"

**Closed:** 2026-10-02 — streaming dictation used throughout the 2026-10-01/02 sessions (WhisperKit and Parakeet EOU live, second pass, Esc → Resume across parts); closed by user decision. The open "EOU silent-paint inconsistency" note from the in-flight row had no further detail; a card-vs-paste mismatch, if seen, is a new bug.

---

### #010 — Drag-suppresses-tap end-to-end test (Test C)

`bug` · `P2` · `done` · `area: pill, testing`
*Updated 2026-10-02*

`mouseDown` → simulated 10pt drag (multiple `mouseDragged` events crossing the 4pt threshold) → `mouseUp`. Assert `onTap` does NOT fire; `onMouseDragged` does. Tests A + B landed (`1cb665c`). State-machine drag test at `PillOverlayPresenterTests.swift:17-34` already exists; this covers the end-to-end hosting-view path.

**Legacy:** `PLAN_PHASES.md` Step 1.4b

**Closed:** `c2ef752` — `PillOverlayPresenterTests.testDragPastThresholdSuppressesTapAndFiresDraggedCallback` drives real mouse events through the hosting view; already shipped when the ticket was filed.

---

### #103 — WhisperKit streaming hangs on finish() after a burst of audio

`bug` · `P3` · `done` · `area: transcription, streaming`
*Opened 2026-10-02 · Updated 2026-10-02*

Repro with the opt-in `StreamingSecondPassBenchmarkTests` (`NINIMMA_BENCH_WAV=…`): feed a recording to `WhisperKitAdapter.transcribe(stream:)` in one burst. `LiveWhisperKitRuntimeBridge.finish()` calls `stopStreamTranscription()`, but `transcriberTask` does not end. Real-time-paced input completes. Burst delivery can occur when capture catches up after a stall; Parakeet EOU completes under the same input pattern.

**Closed:** 2026-10-02 — root cause was a start race, not burst input as such: `startStreamTranscription()` awaits a mic-permission check before it marks itself recording and clears the processor buffer, but `start()` returned immediately. A stop sent in that gap was lost (the loop then ran forever), and audio appended in that gap was wiped. `start()` now waits until the processor reports recording started (or the start task ends). Verified with `NINIMMA_BENCH_PACE=burst` (hung before, finishes after) and the real-time benchmark (unchanged).

---

### #029 — Wire `PillStyle` preference to overlay rendering

`refactor` · `P2` · `done` · `area: pill, theming`
*Updated 2026-10-03*

Preference + Settings picker landed (`ee4d7ca`); the overlay still always renders Classic visuals. When Mini: smaller compact pill. When None: overlay hidden regardless of `PillVisibilityMode`. Requires reconciling with `PillVisibilityMode` semantics.

**Legacy:** `ui-mockup-gaps.md` Settings→General deferred follow-up

**Closed:** 2026-10-03 — merged into #102 point 2 (Style setting wiring).
