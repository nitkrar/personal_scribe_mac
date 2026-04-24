# Ninimma — Backlog Archive

Closed items. Source of truth for "what was the fix for that thing I filed months ago?". Active items live in [`BACKLOG.md`](./BACKLOG.md).

**Note on granularity:** items below are archived by source group rather than one-ticket-per-closed-item. Fine-grained per-item status lives in the original source doc (moved to `plans/_legacy/`) or in git history via the cited commit SHAs.

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

Original source docs moved to `plans/_legacy/` for reconciliation reference (can be deleted a few weeks after this migration once no ticket lookup ambiguity surfaces).

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
