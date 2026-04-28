# Ninimma — Backlog

Canonical active-work registry, GitHub-issues-style. Lives at repo root as of 2026-04-22 (previously `plans/BACKLOG.md`). Closed items live in [`BACKLOG_ARCHIVE.md`](./BACKLOG_ARCHIVE.md). Phase/roadmap context in [`plans/ROADMAP.md`](./plans/ROADMAP.md). Central-layers refactor plans stay at [`plans/central/`](./plans/central/). Pre-migration feature notes + Phase 1/2 closures archived at [`plans/_legacy/BACKLOG_pre_migration.md`](./plans/_legacy/BACKLOG_pre_migration.md).

## Schema

- `type:` bug / feature / refactor
- `priority:` P0 (critical / dogfood blocker) / P1 (schedule actively) / P2 (work in flow) / P3 (wishlist)
- `status:` open / in-progress / blocked / parked / done
- `stage:` design / impl / review / followup *(optional)*
- `phase:` 1 / 2 / 3 / 4 *(optional)*
- `area:` freeform tags

Each ticket has an `*Updated YYYY-MM-DD*` line under the tag row. Bump on meaningful change (status/stage/priority flip, material body edit, new changelog entry). Don't bump for typo fixes.

**IDs:** sequential from `#001`. Never reused. Legacy references kept per-ticket under `**Legacy:**`.

---

## In flight

| Ticket | Owner | Started | Last update | Notes |
|---|---|---|---|---|

**Session naming.** The **main** Claude session running in the user's terminal picks a short single-word identifier (nature words work well — `heron`, `cobalt`, `slate`, `olive`, `rust`) the first time it touches this file and uses it consistently. Subagents dispatched from a main session **inherit its name** — they do NOT claim their own. Only a parallel main session (e.g. a second terminal) picks a distinct name. Don't use `main session` / `parallel session` / `user` as owners — too ambiguous when >1 session is live.

**Claiming a ticket.** When a session starts active work, add a row with today's date in both `Started` and `Last update`, and flip the ticket body status to `in-progress`. Delete the row when the ticket lands or reverts to `open`.

**Updating.** Bump `Last update` on heartbeat, commit, or meaningful status change. Any row with `Last update` > 3 days old = "is this alive?" check — matches the `.codex-heartbeat/` contract.

**Edit only your own rows.** A session may only edit in-flight rows where `Owner` matches its own session name, plus the shared convention text in this section. To change another session's row, ping the user instead.

**Dead-session cleanup.** If every row owned by a given session has `Last update` > 24h old, treat that session as dead. Any other session may delete those orphaned rows when it next touches the file. If a deleted row's ticket body was `in-progress`, flip the ticket body status back to `open` — a fresh session can re-claim. Don't guess at what the dead session accomplished; the commit log is ground truth.

**Blocked on user.** Prefix the Notes cell with `**[needs user]**` so items needing your attention scan first in the table.

**When to commit the backlog file.** Default: **do NOT stage or commit `BACKLOG.md`** unless the user explicitly asks (e.g. "also commit the backlog", "stage the backlog edits"). Ticket-body edits, in-flight-row changes, and `status` flips all accumulate as uncommitted local edits — that's expected and fine. When a session stages code/test changes alongside a ticket landing, **omit `BACKLOG.md` from the `git add` list** unless the user called it out. The user will batch backlog commits when they decide the scheduled drift is worth capturing.

---

## Legacy-ID cross-reference

Quick lookup when an old commit or doc cites a legacy ID.

### From `ui-dogfood-bugs-2026-04-21.md`
- #3 → #005 · #5 → #001 · #7 → #004 · #10 → #034 · #11 → #035 · #12 → #002 · #13 → #007 · #15 → #006 · #17 → #011 · #18 → #008 · #19 → #028

### From `ui-mockup-gaps.md` (open items)
- Transcriptions mode-pill (row) → #032
- Unified-shell + D-follow-up mic footer → #008 (sidebar) / #037 (title-bar accessory)
- Settings→General D-follow-up: PillStyle wiring → #029 · pasteEnabled wiring → #030

### From `PLAN_PHASES.md`
- Step 1.1b (signposts) → #012 · Step 1.4b (drag-tap test C) → #010
- Phase 3.B (Notes) → #013 · 3.C (Onboarding) → #015 · 3.D (SQLite) → #026 · 3.F (2nd model) → #016 · 3.G (hotkey customization) → #017 · 3.H (clipboard clobber) → #018 · 3.I (triple-⌥ quit) → #019
- Phase 4 (Intent) → #020 · (Command Mode cards) → #021 · (Ask Ninimma) → #022 · (Action Dispatcher) → #023

### From other backlog docs
- `backlog/phase-8-cancel-recording.md` → #002 · `backlog/issue-6-pill-panel-focus.md` → #003 · `backlog/transcript-trigger-context.md` → #027 · `backlog/model-download-ux-bug-research.md` Stage B → #009 + #024 + #025 + #036 + #038 · `backlog/streaming-output-delivery-mechanism.md` + `backlog/pipeline-streaming-defer.md` → #033 *(merged)*

### From `plans/central/`
- All layer Stage-2/3 validation work → #031

---

## Bugs

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

### #010 — Drag-suppresses-tap end-to-end test (Test C)

`bug` · `P2` · `open` · `area: pill, testing`
*Updated 2026-04-21*

`mouseDown` → simulated 10pt drag (multiple `mouseDragged` events crossing the 4pt threshold) → `mouseUp`. Assert `onTap` does NOT fire; `onMouseDragged` does. Tests A + B landed (`1cb665c`). State-machine drag test at `PillOverlayPresenterTests.swift:17-34` already exists; this covers the end-to-end hosting-view path.

**Legacy:** `PLAN_PHASES.md` Step 1.4b

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

## Features

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

### #012 — OSSignposter instrumentation for launch-freeze RCA

`feature` · `P3` · `open` · `area: session, observability`
*Updated 2026-04-21*

Wrap `prepareTranscriber()`, `performPrepare()`, `inference.loadModel` with signposts. Measure cold-launch prepare latency objectively so regressions aren't diagnosed by anecdote.

**Legacy:** `PLAN_PHASES.md` Step 1.1b

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

### #014 — Tags on transcripts/notes

`feature` · `P1` · `open` · `phase: 3` · `area: storage, ui`
*Updated 2026-04-21*

Either TEXT column + index, or `tags` + `transcript_tags` relation. Schema choice belongs to the storage-layer plan (#026). Part of #013 Notes scope.

**Depends on:** #026, #013

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

**Known limitations (not filed as follow-up):**
- Modifier-only binding (e.g. double-tap ⌥) is still deliberately unimplemented end-to-end — `HotkeyRecorder.captureModifierChange` rejects any `.flagsChanged` chord, and `GlobalHotkeyMonitor.handle(event:)` no-ops `.flagsChanged` with a comment pointing at future work. User confirmed 2026-04-24 this is acceptable; default `opt + /` is the intended binding. Reintroducing modifier-only input would need recorder + monitor gesture-machine changes in both layers.
- `ReservedInAppHotkeys`'s Esc entry is inert for plain Esc (captured by the recorder's cancel short-circuit first). Kept for `Cmd+Esc`/`Opt+Esc` rejection messaging and as scaffolding for future in-app hotkeys (#068, #070).
- Stale "right Option" strings in `PillOverlayView.swift:216` + `StatusItemMenuModel.swift:262,278` — cosmetic copy drift from the pre-`opt + /` spec; out of scope here.

---

### #018 — Clipboard clobber timing (configurable paste-restore delay)

`feature` · `P3` · `open` · `phase: 3` · `area: output, settings`
*Updated 2026-04-21*

Default 0.5s. Surface in Settings → Advanced.

**Legacy:** `PLAN_PHASES.md` Phase 3.H (UX-audit BUG-07)

---

### #020 — IntentClassifier (NLEmbedding → llama.cpp escalation)

`feature` · `P2` · `parked` · `phase: 4` · `area: session, models`
*Updated 2026-04-21*

Stub protocol exists from Phase 2. Full impl deferred until Phase 3 ships and dogfood exposes intent-style flow needs.

**Legacy:** `PLAN_PHASES.md` Phase 4

---

### #021 — Command Mode pill response cards

`feature` · `P2` · `parked` · `phase: 4` · `area: pill, session`
*Updated 2026-04-21*

Query answer / action confirmation / dictation variants.

**Depends on:** #020
**Legacy:** `PLAN_PHASES.md` Phase 4

---

### #022 — "Ask Ninimma" query flow

`feature` · `P3` · `parked` · `phase: 4` · `area: ui, storage`
*Updated 2026-04-21*

FTS5 + embedding lookup over transcripts/notes. Needs embeddings schema (migration on storage layer).

**Depends on:** #020, #013
**Legacy:** `PLAN_PHASES.md` Phase 4

---

### #023 — Action Dispatcher (NSWorkspace + app-specific APIs)

`feature` · `P3` · `parked` · `phase: 4` · `area: session`
*Updated 2026-04-21*

**Legacy:** `PLAN_PHASES.md` Phase 4

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

### #025 — Model Stage B: disk-space precheck

`feature` · `P2` · `open` · `phase: 3` · `area: models`
*Updated 2026-04-21*

Read `ModelDescriptor.approximateSizeBytes` at Download click. Compare against `FileManager.attributesOfFileSystem[.systemFreeSize]`. Confirmation sheet if free space < 2× download size.

**Legacy:** `backlog/model-download-ux-bug-research.md` Stage B

---

### #045 — Personal dictionary (2-stage)

`feature` · `P2` · `open` · `phase: 3` · `area: post-processing, memory-learning`
*Updated 2026-04-22*

Central to the Memory/Learning competitive pitch (`COMPETITIVE.md`). **Stage A:** refactor `PostProcessor` to a chain-of-stages; add `PersonalDictionaryStage` applied first. Data: `DictionaryEntry { term, alternatives: [String], createdAt, source }`; JSON at `<AppConfig.baseDirectory()>/dictionary.json`. Case-insensitive word-boundary replacement, first match wins per region; no regex. No UI — manual file edit until Phase 3 Settings. Soft cap ~40 entries / 60-char alternatives. **Stage B:** decoder-level biasing via Parakeet CTC custom-vocab head + correction-learning loop from NotesWindow edit UI — `CollectionDifference`-based edit tracking + Levenshtein filter; top-30 decayed-frequency terms feed the CTC vocab.

**Depends on:** #013 (NotesWindow edit UI — Stage B only)
**Legacy:** `plans/_legacy/BACKLOG_pre_migration.md` → "Personal dictionary — ship in two stages"

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

### #047 — Auto-pause playback during recording (2-stage)

`feature` · `P3` · `open` · `area: audio, output, dictation`
*Updated 2026-04-22*

**Stage A:** on `SessionCoordinator.start()`, read UserDefaults `AutoPausePlayback` (default `true`). If enabled, send `MPRemoteCommandCenter.shared().pauseCommand` — system-wide pause for active media app. No auto-resume. No Settings UI until Stage B. **Stage B (with Phase 3 Settings):** toggle bound to the same UserDefaults key + optional opt-in auto-resume after session ends. **Meeting-mode caveat:** disable auto-pause when meeting mode is active (dual-track needs system audio playing).

**Legacy:** `plans/_legacy/BACKLOG_pre_migration.md` → "Auto-pause playback during recording"

---

### #048 — Active window context capture (2-stage)

`feature` · `P2` · `open` · `phase: 3` · `area: session, storage`
*Updated 2026-04-22*

Substrate for future smart-routing + mode rules. **Stage A:** new `RecordingContext { bundleIdentifier, appName, capturedAt }` in `PersonalScribeCore`. Optional `context` field on `TranscriptEntry` (schema additive — Codable optional handles back-compat). At hotkey-press, read `NSWorkspace.shared.frontmostApplication` via a `FrontmostAppProviding` protocol (mirrors `PasteInjector`'s capture-before-Ninimma-focus pattern). Pass through `SessionCoordinator.start()`. No UI, persist metadata only. Unknown context = valid `nil`. **Stage B:** opt-in window title (AX — already have permission) + browser URL (per-browser scripting). Privacy-sensitive — never Stage A.

**Blocks:** #057 (app-context mode-selection rules consume this substrate)
**Legacy:** `plans/_legacy/BACKLOG_pre_migration.md` → "Active window context capture — ship in two stages"

---

---

### #059 — Dual-track recording (mic + system audio)

`feature` · `P2` · `open` · `phase: 4` · `area: audio, meeting`
*Updated 2026-04-22*

`ScreenCaptureKit` audio tap (macOS 13+). Mic track = "me" trivially; diarize only the system-audio track. Precondition for meeting mode. Fundamental change from today's mic-only capture (which mixes speaker leakage into a single stream).

**Blocks:** #061
**Legacy:** `plans/_legacy/BACKLOG_pre_migration.md` → "Dual-track recording"

---

### #060 — Voice identification + cross-session speaker DB (absorbs #049)

`feature` · `P2` · `open` · `area: session, dictation, meeting`
*Updated 2026-04-22*

**Absorbed #049 (me-vs-other speaker verification) on 2026-04-22.** One ticket for all voiceprint-based speaker identification, whether the user is tagging "me" or any named other speaker. The N=1 case (just "me" enrolled) is functionally identical to the N>1 case — same plumbing. Design rationale + Q&A lives in [`plans/speaker-diarization-design.md`](./plans/speaker-diarization-design.md).

**Stage A (minimum):** voiceprint DB at `<AppConfig.baseDirectory()>/speakers.json` storing N entries of `{ name, embedding, enrolledAt, source }`. No dedicated "Enroll my voice" ceremony — after any recording where diarization finds > 1 cluster (or duration exceeds a threshold), show a post-stop prompt *"Tag speakers for this recording?"*. Each cluster renders as a short audio snippet; user types a name or skips. On save, voiceprint is persisted. Subsequent recordings: seed Pyannote's `DiarizerManager` via `initializeKnownSpeakers(allStored)` — matched clusters auto-label by name, unmatched → `speaker 2` / `speaker 3` etc. User can retroactively rename any cluster (including unmatched ones — saves a new voiceprint). Solo-speaker recordings don't prompt.

**Stage B (dogfood-gated):** Settings UI for DB management (rename / delete / merge speakers), threshold tuning, low-confidence warnings, optional auto-label-me heuristic after N frequent solo-speaker recordings.

**Open unknowns** *(carry into implementation planning)*: Pyannote pipeline size + peak RAM (measure `FluidInference/speaker-diarization-coreml` once); whether `speakerThreshold: 0.65` is appropriate; prompt-noise tuning (duration + cluster-count thresholds); solo-dictation auto-label heuristic for Stage B; clustering-anchor false-positive behavior when a new voice is close to an enrolled one.

**Supersedes:** #049.
**Blocks:** #061.
**Legacy:** `plans/_legacy/BACKLOG_pre_migration.md` → "Me-vs-other speaker verification" + "Cross-session speaker recognition"
**Design:** [`plans/speaker-diarization-design.md`](./plans/speaker-diarization-design.md)

---

### #051 — Lifetime + historical time-saved analytics

`feature` · `P3` · `open` · `area: metrics, ui`
*Updated 2026-04-22*

Partial coverage exists via Home rollups (`SQLiteMetricsService` rolling-7-day windows — landed in #026). Remaining scope: expose lifetime totals, per-mode breakdowns, historical trends. Home for this UI: new Stats view, or extend Transcriptions tab with a summary strip.

**Legacy:** `plans/_legacy/BACKLOG_pre_migration.md` → "Time-saved analytics"

---

### #052 — Voice tags / micro-prompts

`feature` · `P3` · `open` · `area: session, dictation`
*Updated 2026-04-22*

Prefix a recording with a short tag word ("reminder", "email Alice", "todo") that drives downstream routing or labeling. Overlaps conceptually with #057 (app-context mode-selection rules) — investigate whether voice tags subsume, complement, or compete with context rules before scoping implementation.

**Legacy:** `plans/_legacy/BACKLOG_pre_migration.md` → "Voice tags, micro-prompts"

---

### #056 — Streaming dictation mode (EOU partials + v3 final)

`feature` · `P2` · `open` · `phase: 4` · `area: dictation, session`
*Updated 2026-04-22*

Separate hotkey from quick mode. EOU 120M partials render in the overlay pill only (no paste during streaming); v3 batch re-transcribes on stop to produce the final pasted text. ~850MB ANE footprint while active. English-only. Precondition for #057 (app-context rules).

**Legacy:** `plans/_legacy/BACKLOG_pre_migration.md` → "Streaming dictation mode"

---

### #078 — Adapter layer for non-`parakeetTDT` model families

`feature` · `P0` · `done` · `phase: 4` · `area: transcription, models, architecture`
*Updated 2026-04-28*

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
- `10a81f0` — **runtime memory eviction fix.** Process was hitting 4.77GB resident with 3.86GB MALLOC_LARGE because `SessionPipelineOrchestrator.makeProgressForwardingTask` captured `lifecycle` strongly via the for-await header AND `FluidAudioDownloadProgressBroadcaster` had no `deinit`. Each Activate switch left the previous adapter pinned forever. Fix: extract `let stream = lifecycle.modelDownloadProgress()` outside the Task body so the closure captures the AsyncStream value, not the adapter; broadcaster `deinit` calls `continuation.finish()` on outstanding subscribers. Together breaks the retention cycle.

**Test status:** 1081 tests, 1 skipped, 0 failures. Tap-to-record + hold-to-record + Activate-switch + Download/Delete flows verified on 2026-04-27/28.

**Pending runtime verification** (post-`10a81f0`): user testing on the Air to confirm process RSS tracks only the currently active model's footprint, not the cumulative sum across switches.

**Open follow-ups (filed separately):**
- `#078.39` — manual verification artefacts (Qwen3 entry in `ManualTranscriptionVerification.md`; streaming + diarizer checklists deferred until #056/#058/#061 ship UI consumers).
- `#088` — narrow FluidAudio model download to runtime-needed files (P2 refactor — Qwen int8 lands ~2.9GB for a 1.25GB runtime due to FluidAudio's `isMetadata` carve-out admitting `.bin/.json/.model` from any nested dir under subPath, scooping up v1 + `.mlpackage` siblings).

**Legacy:** session-generated 2026-04-25 from #024.6 catalog expansion follow-up.

---

### #057 — App-context rules for mode selection

`feature` · `P2` · `open` · `area: dictation, session`
*Updated 2026-04-22*

Frontmost-app rules: `Notes/Word/Pages → long-form`, `Slack/iMessage → quick`. Not FluidAudio-specific. Needs both the context substrate and the streaming mode to be meaningful.

**Depends on:** #048 (context capture substrate), #056 (streaming mode)
**Legacy:** `plans/_legacy/BACKLOG_pre_migration.md` → "App-context rules for mode selection"

---

### #064 — Landing page / website

`feature` · `P3` · `open` · `area: distribution, pre-launch`
*Updated 2026-04-22*

Pre-public-launch marketing page. Single page: pitch from `PROPOSAL.md` + screenshots + download link + privacy stance. Static hosting; no backend.

**Legacy:** `plans/_legacy/BACKLOG_pre_migration.md` → "Future (not yet scoped)"

---

### #065 — Homebrew distribution

`feature` · `P3` · `open` · `area: distribution, packaging, pre-launch`
*Updated 2026-04-22*

Homebrew cask formula so `brew install --cask ninimma` works. Handles DMG download + `/Applications/` install. Coordinates with first-run permission prompts; document the TCC ad-hoc-path quirk so `brew`-installed + DMG-installed copies don't collide.

**Legacy:** `plans/_legacy/BACKLOG_pre_migration.md` → "Future (not yet scoped)"

---

### #066 — Accessibility audit

`feature` · `P2` · `open` · `area: a11y, pre-launch`
*Updated 2026-04-22*

Full VoiceOver pass: menu-bar interactions, pill states (recording / hold-to-record / transcribing), Settings tabs, Transcriptions tab, Notes window. Keyboard navigation for non-pointer users. Contrast checks against `Palette` tokens under warm / neutral / dark tints.

**Legacy:** `plans/_legacy/BACKLOG_pre_migration.md` → "Future (not yet scoped)"

---

### #067 — Data-at-rest encryption (SQLCipher)

`feature` · `P3` · `open` · `area: storage, security`
*Updated 2026-04-22*

Migrate `transcripts.sqlite` to SQLCipher-backed encrypted DB. Key via Keychain. Needs GRDB-SQLCipher integration (replaces GRDB system-SQLite linkage). Useful for shared-machine users / stronger than current `0600` perms. Requires migration path on upgrade.

**Depends on:** #026 (done — single DB owner in place)
**Legacy:** `plans/_legacy/BACKLOG_pre_migration.md` → "Future (not yet scoped)"

---

### #068 — In-pill mode switcher (quick UX)

`feature` · `P2` · `Stage A done · Stage B pending` · `phase: 3` · `area: pill, ui, modes`
*Updated 2026-04-24*

Switch the active mode directly from the pill overlay (or the menu-bar status item) instead of having to open Settings → Modes tab. Today mode switching is a multi-click journey through the unified window; this ticket makes it a one-click flip next to where the user is already looking.

**Status (2026-04-24)** — Stage A shipped (menu-bar submenu). Stage B (pill bottom-row icon) deferred until a second mode lands; with `ModeRegistry.all = [dictation]` today the menu-bar submenu is one-item scaffolding that auto-lights-up when modes infra grows.

**Locked design decisions (2026-04-24 session):**
- **Where**: menu-bar "Mode" submenu (Stage A) + pill bottom-row icon → click opens picker (Stage B). Click-only — no hover chip, no long-press.
- **Modes listed**: all wired modes including user-defined; unwired modes hidden until they have distinct behavior.
- **When it applies**: immediately (next session starts in new mode). Mid-recording flip out of scope.
- **Keyboard chord**: dropped. Discoverability problem (no way to surface the cycle direction) outweighed the speed win.

**Stage A — DONE** (`bf28dd3`, 2026-04-24): menu-bar "Mode" submenu. Mirrors `StatusItemMenuModel` Microphone-submenu pattern via a new `.modeSubmenu` `Item` + `ModeSubmenuChild`. Lists `ModeRegistry.all`, checkmark on the active mode, selection routes through `modelService.setActive(modelService.descriptor(for: mode))` — same closure shape as the existing `UnifiedWindowController` ModesTab path. Snapshot observer rebuilds the menu on `activeMode` change → checkmark + parent title update automatically. Tests: 2 new in `StatusItemMenuModelSubmenuTests` + 9 existing mic-submenu tests + 20 baseline `StatusItemMenuModelTests` all pass. Runtime click-through not yet manually verified.

**Stage B — PENDING**: pill bottom-row mode icon → click opens picker. Real architectural cost; explicitly NOT minimal.
- Pill geometry today is single-row HStacks at fixed dimensional bands (`PillOverlayView.swift:40-78`, `size(for:)` at L96-119). Adding a row changes the height bands and breaks the `PillOverlayPresenter` per-state panel-resize tween (#044).
- Sub-region clicks inside the pill don't fire SwiftUI gestures — `ClickThroughHostingView.mouseDown` overrides without `super`. Needs AppKit hit-testing for the new icon region (see memory `project_pill_hit_testing`).
- Click target needs to open a picker against a non-activating `NSPanel` — popover plumbing not currently wired anywhere on the pill.
- Per-state visibility (does the icon show during recording / downloading / error?) is a design call.

**Stage B preconditions:** (a) ≥ 2 wired modes exist (otherwise Stage B is shipping complex infra to point at a list-of-one); (b) decision on whether the icon shows in active-recording states or only in idle.

**Depends on:** none for Stage A (ModesTab + `ModeDescriptor` already live). Stage B effectively blocked on additional modes infra landing.
**Legacy:** none — net-new ticket from 2026-04-22 UX session.

---

### #069 — Persist audio recordings on disk

`feature` · `P2` · `open` · `phase: 3` · `area: audio, storage, session`
*Updated 2026-04-22*

Today audio lives only in `SessionCoordinator.bufferedAudio: [PCMBuffer]` in memory and is dropped after transcription. The `recordings/` directory name is aspirational — `AppConfig.swift:71` literally comments "Reserved for future recordings/ feature." This ticket fills that gap.

**Why now:** unlocks re-transcription with upgraded voice models, audio replay from the Transcriptions tab, retroactive diarization (re-run #058 / #060 on past recordings), and export. Today all of those require re-capturing the audio.

**Stage A (minimum):** on `SessionCoordinator` stop, write the in-memory buffer as `.wav` (16 kHz mono 16-bit — native capture format, no encoding step) to `<AppConfig.recordingsDirectory()>/<UUID>.wav`. Add an optional `audioFilePath: String?` column to the `transcripts` table via a new migration registered in `TranscriptsMigrator`; the column stores the relative filename, not a full path (base directory is resolved at read time). `TranscriptRepository.append(_:)` writes the path alongside the entry in one transaction. UI: none — metadata-only for now. Feature gate: `RecordAudioEnabled` UserDefaults default `true`; off means fire-and-forget capture (today's behavior).

**Stage B (dogfood-gated):** retention policy — configurable default (suggest 30 days) via a background sweeper that deletes `.wav` files older than N days and nulls the corresponding `audioFilePath` column. Settings UI under Advanced → "Audio recordings" section: toggle, retention slider, current disk-usage readout, "Delete all recordings" button. Compression (`.m4a` or `.caf` via `AVAudioFile` encoding) only if uncompressed disk usage proves painful — `.wav` at 2 MB/minute means a 1-hour meeting is 120 MB; 30-day retention at 10 min/day is ~600 MB. Measure real usage first.

**Open questions:**
- Format: start `.wav` (no encoding, simplest) or jump straight to compressed? Recommend `.wav` for MVP.
- Retention default: 30 days / 90 days / never? Lean 30 days with Settings slider.
- Disk-space guardrail: warn or hard-stop when recordings dir exceeds X GB?
- Transcript deletion (#011) — should it cascade to the audio file?
- Filesystem permissions: mirror the DB's `0600`.

**Depends on:** #026 (schema migration via `TranscriptsMigrator` — done).
**Unlocks:** #058 retroactive diarization, #060 retroactive voice-ID re-tagging, "replay audio" UI in Transcriptions tab, "re-transcribe" action after upgrading the voice model.
**Legacy:** `Sources/PersonalScribeCore/Storage/AppConfig.swift:71` comment — "Reserved for future recordings/ feature" has been reserved since Phase 1.

---

### #070 — Recording pause/resume (pill affordance)

`feature` · `P2` · `open` · `area: session, pill, audio`
*Updated 2026-04-22*

Replace pill ✕ with a pause/play toggle on pill-click-initiated recordings. Pausing retains the captured audio buffer; resume continues appending; final stop (click pill, or a stop affordance in paused state) transcribes the whole buffer. Esc remains the sole discard path (per #002) once this ships — ✕ goes away entirely.

**Scope:**
- New session state `.paused` alongside `.recording` / `.transcribing`; buffer retention across pause boundaries.
- `SessionCoordinator.pauseRecording() async` + `resumeRecording() async`; `SessionPipelining.pauseCapture()` / `resumeCapture()`.
- Audio capture actor: stop emitting samples without tearing down `AVAudioEngine` input (keep tap installed, pause buffering) OR stop the engine and re-prime on resume — evaluate latency/correctness of each.
- Pill UI: pause/play icon in place of ✕; visual indicator for paused state (dimmed equalizer bars? frozen waveform?); recording-duration timer pauses.

**Open questions:**
- Timeout: auto-transcribe after N minutes paused, or hold indefinitely?
- Interaction with VAD auto-stop (#046) — does VAD trigger auto-pause, auto-stop, or do nothing while paused?
- Menu-bar "Stop" path while paused — transcribe or discard?
- Paused state needs a stop-and-transcribe affordance distinct from resume — pill-click, long-press, secondary button?

**Out of scope:** hold-to-record flow — that path uses a separate pill with no Esc/✕/pause affordance; release always stops + transcribes.

**Depends on:** #002 (locks `✕ = true-discard` semantics first; #070 then reclaims that slot for pause/play and removes the ✕).
**Legacy:** 2026-04-22 brainstorm (after #002 spec-literal lock).

---

## Refactors

### #088 — Narrow FluidAudio model download to runtime-needed files

`refactor` · `P2` · `open` · `area: transcription, models, downloads`
*Filed 2026-04-28*

`DownloadUtils.downloadRepo` (FluidAudio) over-pulls when a repo's
subPath contains sibling directories or duplicate model formats.
Concrete case: Qwen3-ASR int8 lands ~2.9 GB on disk for an int8
runtime that only needs ~1.25 GB. The bloat:

- `qwen3_asr_audio_encoder.mlmodelc` (v1, ~369MB) + `.mlpackage` (~368MB)
  alongside the v2 the runtime actually loads (~370MB compiled).
- `qwen3_asr_decoder_stateful.mlpackage` (~577MB) alongside the
  `.mlmodelc` we use (~578MB).

**Root cause** (FluidAudio bug): the listing recursion
(`DownloadUtils.swift:321-355`) admits any directory whose path
starts with the subPath, then admits any nested file matching
`isMetadata` — `.json` / `.model` / `.bin` extensions — regardless
of whether the parent directory was named in the pattern list.
`.mlmodelc` and `.mlpackage` directories contain `weights.bin` and
`coremldata.bin` files; the carve-out scoops them up.

**Why ours-not-FluidAudio.** We already bypassed FluidAudio's
higher-level `Qwen3AsrModels.download` (which silently dropped the
`to:` argument) by calling `DownloadUtils.downloadRepo` directly
from `LiveFluidAudioQwenManager`. We're already one step from
"replace the only FluidAudio download call with our own."

**Scope.** A shared narrower wrapper used by every adapter, not a
Qwen-only special case. Per-adapter forks would re-introduce the
duplication we just collapsed in #094 (the shared
`FluidAudioDownloadProgressBroadcaster` consolidation).

Approach (sketch):
- New `FluidAudioDirectDownloader` in `PersonalScribeTranscription`
  using FluidAudio's public lower-level API:
  `DownloadUtils.downloadSubdirectory(_ repo:subdirectory:to:)`
  (line 521 of `DownloadUtils.swift`) per `.mlmodelc` directory the
  descriptor's `requiredRelativePaths` declares, plus a small
  URLSession fetch helper for top-level metadata files (vocab.json,
  embeddings.bin) via `ModelRegistry.resolveModel(remotePath:filePath:)`.
- Adapter manager protocols' `downloadIfNeeded(...)` route through
  this wrapper instead of `DownloadUtils.downloadRepo`. All four
  adapters change in lockstep — no Qwen-specific path.
- Descriptor's `requiredRelativePaths` becomes the contract; the
  wrapper enforces it. Drift between descriptor and FluidAudio's
  `requiredModelsFull` enums is now visible at our layer.

**Tradeoff.** We own the download path, including future FluidAudio
release tracking. If FluidAudio adds a required file we don't list,
runtime fails. Mitigation: pin the FluidAudio version + add a smoke
test that loads each registered model from its descriptor's required
paths.

**Alternative.** File upstream issue + PR against FluidAudio to
tighten `downloadRepo`'s metadata carve-out (constrain to depth-1
under subPath, AND require pattern-list match for nested
directories). Cleaner architecturally but slower + we don't control
release cadence.

P2 because the bloat is one-time per model activation (not
per-session) and the user can manually clean unused files. Bumps to
P1 if dogfood disk pressure becomes an issue or if a model variant
bloats >2× its declared size and breaks the disk-space precheck.

**Legacy:** session-generated 2026-04-28 from Qwen int8 download
inspection (#078 follow-up).

---

### #074 — State-ownership audit across app

`refactor` · `P0` · `open` · `area: architecture`
*Filed 2026-04-24*

State ownership keeps fragmenting during ostensibly-simple tasks: the same concept lives in multiple places coupled to different state machines. Recurring pattern, not tied to any single class.

**Examples:**
- **Consolidated (good precedent):** session + capture pipeline (see `plans/central/`). One coordinator, one state machine.
- **Previously fragmented (unified as part of #072):** clipboard snapshotting split across `PasteboardSnapshotService` (session-lifecycle) and `ClipboardBatchOutput.savedItems` (output-pipeline). Landed as one consolidated `PasteboardSnapshotService` with durable `.cancelUndo` slot + transient handles.

Audit scope intentionally left open. Walk state concepts, not classes. Details filled in during the audit — not now.

---

### #027 — TranscriptEntry needs `modeId` + `trigger`

`refactor` · `P2` · `parked` · `stage: design` · `phase: 4` · `area: storage, session`
*Updated 2026-04-21*

Schema evolution driven by Command Mode. `ModeDescriptor` soft-delete/tombstone for reference integrity. Trigger field may be dropped if pure signal-noise.

**Depends on:** #026, #021
**Legacy:** `backlog/transcript-trigger-context.md`

---

### #028 — Central KeyEventRouter consolidation (5a-v2)

`refactor` · `P1` · `open` · `stage: design` · `area: hotkey`
*Updated 2026-04-21*

One router owning `CGEventTap` + `NSEvent` local-monitor pair; migrate `GlobalHotkeyMonitor`, `EscapeKeyMonitor`, `HotkeyRecorder`, and ad-hoc `addLocalMonitorForEvents` callers. ~3-5 commits. Do NOT bundle with #001's bug fix.

**Depends on:** #001 shipping first
**Legacy:** `ui-dogfood-bugs-2026-04-21.md` #19

---

### #029 — Wire `PillStyle` preference to overlay rendering

`refactor` · `P2` · `open` · `area: pill, theming`
*Updated 2026-04-21*

Preference + Settings picker landed (`ee4d7ca`); the overlay still always renders Classic visuals. When Mini: smaller compact pill. When None: overlay hidden regardless of `PillVisibilityMode`. Requires reconciling with `PillVisibilityMode` semantics.

**Legacy:** `ui-mockup-gaps.md` Settings→General deferred follow-up

---

### #030 — Wire `pasteEnabled` master toggle to OutputService

`refactor` · `P2` · `open` · `area: output, settings`
*Updated 2026-04-21*

Preference + Settings toggle landed (`41c3f6c`); when disabled, should suppress both paste AND clipboard write.

**Legacy:** `ui-mockup-gaps.md` Settings→General deferred follow-up

---

## Parked

### #049 — Me-vs-other speaker verification *(superseded by #060)*

`feature` · `P3` · `parked` · `area: session, dictation, meeting`
*Updated 2026-04-22*

**Superseded by #060 on 2026-04-22.** Scope — single-voiceprint enrollment for "me" + binary me/other labeling — collapsed into #060 as the N=1 case of a generalized voiceprint DB. Same plumbing for 1 voiceprint vs N; no reason to split the work. See [`plans/speaker-diarization-design.md`](./plans/speaker-diarization-design.md) for the Q&A that drove the merge.

ID retained for traceability (IDs never reused). No scheduled work — new voice-ID work goes on #060.

**Supersedes:** —
**Superseded by:** #060
**Legacy:** `plans/_legacy/BACKLOG_pre_migration.md` → "Me-vs-other speaker verification — ship in two stages"

---

### #032 — Mode pill on transcript rows

`feature` · `P3` · `parked` · `stage: design` · `area: ui`
*Updated 2026-04-21*

Mockup shows "Dictation Mode" / "Command Mode" pill on each row's trailing edge. Requires schema change (#027).

**Depends on:** #027 (and implicitly #021)
**Legacy:** `ui-mockup-gaps.md` Transcriptions row

---

### #033 — Streaming output transport decision

`refactor` · `P3` · `parked` · `stage: design` · `area: output, session`
*Updated 2026-04-21*

`OutputService.beginStream()` API landed (L5 Stage 1); `PipelineOutputSink.deliverPartial` dormant (L7 Stage 1). Transport choice gated on review: `CGEvent` incremental typing vs. chunked pasteboard + synthetic ⌘V. No production consumer permitted until decision. Undo grouping, rate limit, EOU semantics, Unicode fidelity all open.

**Legacy:** `backlog/streaming-output-delivery-mechanism.md` + `backlog/pipeline-streaming-defer.md` *(merged — same decision from two layer seats)*

---

### #034 — Waveform decay tuning

`feature` · `P3` · `parked` · `area: pill`
*Updated 2026-04-21*

Tune falloff on the pill waveform so bars don't snap to zero.

**Legacy:** `ui-dogfood-bugs-2026-04-21.md` #10

---

### #035 — Hold-hotkey mode bar visuals

`feature` · `P3` · `parked` · `area: pill, hotkey`
*Updated 2026-04-21*

Spacing / contrast / motion pass. Capture specifics when picked up.

**Legacy:** `ui-dogfood-bugs-2026-04-21.md` #11

---

### #036 — FluidAudio revision-pin follow-up

`feature` · `P3` · `parked` · `area: models`
*Updated 2026-04-21*

`ModelDescriptor.revision` currently decorative; FluidAudio `ModelRegistry.resolveModel` hard-codes `resolve/main/`. Reinstate when FluidAudio exposes a `revision:` parameter (upstream ask).

**Legacy:** `backlog/model-download-ux-bug-research.md` Stage B

---

### #037 — Mic device title-bar accessory

`feature` · `P3` · `parked` · `area: ui, audio`
*Updated 2026-04-21*

Unified-window chrome readout — "MacBook Pro Microphone (Default)". Overlaps with `AudioInputDeviceProviding` wiring for #008; pick up after that lands.

**Depends on:** #008 decision
**Legacy:** `ui-mockup-gaps.md` Settings→General deferred follow-up

---

### #038 — AI-models Stage B: "AI models" settings section

`feature` · `P3` · `parked` · `phase: 4` · `area: settings`
*Updated 2026-04-21*

Second `SettingsSection` below Voice models; seeds once Phase 4 lands an LLM downloader. `ModelRow` presenter already engine-agnostic.

**Depends on:** #020
**Legacy:** `backlog/model-download-ux-bug-research.md` Stage B

---

### #050 — Correction tracking / auto-learning

`feature` · `P3` · `parked` · `phase: 4` · `area: memory-learning, notes`
*Updated 2026-04-22*

Diff user-edited transcript vs original via `CollectionDifference`; pair removals with nearby insertions; filter by Levenshtein distance. Feeds #045 Stage B dictionary frequency ranking (top-30 decayed-frequency terms → CTC vocab bias). Requires NotesWindow edit UI to observe edits.

**Depends on:** #013 (NotesWindow edit UI), #045 Stage A
**Legacy:** `plans/_legacy/BACKLOG_pre_migration.md` → "Correction tracking / auto-learning"

---

### #054 — Smart auto-archive

`feature` · `P3` · `parked` · `phase: 3` · `area: notes, storage`
*Updated 2026-04-22*

Auto-archive transcripts older than N days or shorter than M chars; hide from primary Transcriptions view, keep searchable via FTS. Specific policy (N / M / archive criteria) TBD — parked until dogfood reveals what becomes cruft.

**Legacy:** `plans/_legacy/BACKLOG_pre_migration.md` → "Smart auto-archive"

---

### #055 — Full clipboard save/restore (all pasteboard types)

`feature` · `P3` · `parked` · `area: output`
*Updated 2026-04-22*

Extend the Phase 5 Cancel Card Undo path from `.string`-only to all `NSPasteboard` types (RTF, images, file URLs, custom UTIs). Needed when a user dictates into a context where they had non-string clipboard contents and then discards via Cancel Card.

**Legacy:** `plans/_legacy/BACKLOG_pre_migration.md` → "Full clipboard save/restore (all pasteboard types)"

---

### #053 — 7-stage post-processing pipeline

`feature` · `P2` · `parked` · `area: post-processing, memory-learning`
*Updated 2026-04-22*

Extend #045 Stage A's chain-of-stages architecture with named stages that add new transformation behavior: ITN → punctuation → filler removal → personal dictionary → capitalization → disfluency repair → formatter. Each stage is additive output cleanup, not a restructuring of existing logic. ITN (Inverse Text Normalization) subsumes FluidAudio `CustomPronunciation.md` path.

**Depends on:** #045 Stage A (the chain architecture must exist first)
**Legacy:** `plans/_legacy/BACKLOG_pre_migration.md` → "7-stage post-processing pipeline"

---

### #058 — Speaker diarization (LS-EEND, up to 10 speakers)

`feature` · `P3` · `parked` · `phase: 4` · `area: meeting, audio`
*Updated 2026-04-22*

FluidAudio LS-EEND: 10 speakers max, 100ms streaming updates, single model. Sortformer optional (4 speakers, stronger identity, NVIDIA Open Model License — licensing trade-off). Building block for #061 Meeting mode.

**Blocks:** #061
**Legacy:** `plans/_legacy/BACKLOG_pre_migration.md` → "Speaker diarization (LS-EEND default)"

---

### #061 — Meeting mode

`feature` · `P3` · `parked` · `phase: 4` · `area: meeting, dictation`
*Updated 2026-04-22*

Zoom/Teams/Webex auto-detect + dual-track capture + diarization + cross-session speaker names. Composes #058 + #059 + #060 into a product-facing feature. Dual-track (#059) splits me from remote-audio cheaply; LS-EEND (#058) splits the remote-audio side into unnamed clusters; #060's voiceprint DB names them.

**Depends on:** #058, #059, #060
**Legacy:** `plans/_legacy/BACKLOG_pre_migration.md` → "Meeting mode"
**Design:** [`plans/speaker-diarization-design.md`](./plans/speaker-diarization-design.md)

---

### #062 — TTS for assistant speaking back (Kokoro + PocketTTS)

`feature` · `P3` · `parked` · `phase: 4` · `area: assistant, audio`
*Updated 2026-04-22*

Kokoro 82M parallel (SSML, pronunciation control) + PocketTTS streaming with voice cloning. English-only initially. Enables voice-out for Ask Ninimma (#022) and Action Dispatcher (#023) confirmations.

**Depends on:** #022 OR #023 (a consumer)
**Legacy:** `plans/_legacy/BACKLOG_pre_migration.md` → "TTS for assistant speaking back"

---

### #063 — MCP server exposing transcripts

`feature` · `P3` · `parked` · `phase: 4` · `area: assistant, storage`
*Updated 2026-04-22*

Wishlist — build only on actual demand. Stage A shape: standalone stdio binary (~200–300 LOC SPM executable target) reading `transcripts.sqlite` via `TranscriptRepository`, exposing read-only tools `search_transcripts` / `list_recent_transcripts` / `get_transcript`. No in-app HTTP server unless Stage A proves insufficient. Privacy caveat at opt-in time (transcripts contain sensitive speech).

**Legacy:** `plans/_legacy/BACKLOG_pre_migration.md` → "MCP server exposing transcripts"
