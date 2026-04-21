# UI Dogfood Bugs — 2026-04-21

User-reported issues from a dogfood build of Ninimma. Captured verbatim as a punch list; triage / root-cause / fix commits come later. Each item is a discrete bug-or-polish — do NOT collapse into one mega-commit.

Legend: `[ ]` open · `[~]` in progress · `[x]` fixed (reference commit)

## Critical (blocks usable flow)

- [~] **1. About tab traps navigation.** Opening the About tab disables tab switching — no way to return to Home/other tabs. After About is opened once, subsequent "Open Home" actions still land on About. Likely a tab-state / default-selection bug that latches onto About.
  - **1a FIXED** (`726e538`) — menu-bar "Home" now routes to the Home tab via `showWindow(selecting: .home)`.
  - **1b** Left sidebar pane must always be visible — `NavigationSplitView` should pin `columnVisibility = .all`.
  - **1c** Move "About" out of Settings sub-tabs and render it as a clickable footer row at the bottom of the sidebar (styled like the Microphone footer — compact, muted — NOT like Home/Transcriptions/Modes/Settings tab rows).
- [x] **4. Global hotkey dies when app window is frontmost.** Switching between full-screen apps and the main desktop (where Ninimma's window is focused) kills the hotkey on the focused space. Hotkey only works when app is NOT in the foreground. Event-tap scope / key-down capture regression. — FIXED: add `addLocalMonitorForEvents` alongside the existing global monitor; swallow matching events so `÷` doesn't leak into our own text fields. Does NOT address `÷` leakage into other apps (that's #5, needs a CGEventTap).
- [ ] **5. Hold-to-record writes `÷÷÷÷÷÷÷` then drops the transcript.** Holding `opt + /` types the `÷` character repeatedly for the duration of the hold and then does NOT paste the transcription. Two bugs: (a) key-swallow failing on hold, (b) paste-on-release broken. Revisit the opt+/ tap/hold/double-tap model (phase 7 pill UX work).
- [x] **9. Menu bar "Copy last transcript" is a no-op.** — FIXED: renamed action to "Copy Last Transcript", implementation is now strict copy-to-clipboard via CopyLastTranscriptAction (no paste attempt, no AX branching). Silent no-op on empty history replaced with a logged outcome; a user-visible toast is deferred to a general feedback polish pass.
- [ ] **12. Esc during recording behaves like Stop, not Cancel.** Esc should discard the in-flight recording *without* writing anything to the clipboard. Today it commits whatever was captured so far (same behavior as Stop). See Phase 8 cancel-without-transcribe backlog — this is the user-visible symptom.

## Sidebar

- [ ] **18. Microphone footer label in left pane is inert.** A small "Microphone" label sits at the bottom of the left sidebar but clicking / hovering does nothing — no menu, no picker, no tooltip. Decide intent: should it (a) open a mic picker popover, (b) route to Settings → input device, (c) display the currently selected input as a status readout only, or (d) be removed? Pick one and wire it (or strip the label).

## Menu bar

- [x] **2. Hide "Check for Updates" from menu bar.** — FIXED: removed the stub entry entirely; will be re-added when the updater pipeline ships.
- [ ] **6. "Ninimma — dictation" wraps to 2 lines in the menu bar.** Expected: single compact line. Likely label width / separator issue.
- [ ] **16. Add "Settings" and "History" entries to the menu bar.** Today the menu bar only opens Home via "Open Home". Add two more actions that route to their respective tabs: Settings → `showWindow(selecting: .settings)`, History (aka Transcriptions) → `showWindow(selecting: .transcriptions)`. Same pattern as the #1a fix.

## Settings — General

- [ ] **3. "Launch at Login" toggle doesn't trigger the system-settings / permission flow.** Toggling ON silently flips state but never prompts or requests the Login Items permission. Verify `SMAppService` / helper invocation is actually firing.
- [x] **8. "Settings" section label above the tab strip is redundant and wraps on default width.** — FIXED: removed the redundant "Settings" largeTitle above the sub-tab picker in SettingsTab.swift — window chrome + sidebar row already identify this as Settings.
- [ ] **14. "Shortcuts" tab has only one row — demote to a subsection inside General.** Currently Shortcuts is its own standalone Settings sub-tab containing a single row (`Record / stop dictation` hotkey). That's wasted surface. Move the row into a new **"Shortcuts"** subsection at the bottom of the General sub-tab; remove the standalone Shortcuts sub-tab + its enum case. Delete `ShortcutsTab.swift` after relocating its content.

## Settings — Advanced

- [ ] **15. Base-directory control is clunky.** Full "Base directory" label plus oversized buttons stack onto the next line. Compact the layout. Also: "Open in Finder" opens the *parent* (`~/Library/Application Support/`) instead of the project's own folder (`…/personal_scribe/`). Fix the URL being passed to `NSWorkspace.open`.

## Settings — AI Models

- [ ] **13. Model labels ("Parakeet TDT", "Parakeet CTC") are opaque.** Size is helpful but users can't tell what's different. Add a one-line description or an info popover per row, and tighten row density so multiple models fit without scrolling.

## Transcriptions / History tab

- [ ] **17. No per-row delete button on transcription history.** Each history row needs an inline delete affordance (trash icon on hover, or swipe action) so users can prune transcripts one at a time. Verify the delete propagates through the transcript store, not just the view-model cache.

## Theming

- [ ] **7. Pill theme / window tint consolidation isn't reflected in the latest build.** Recent commits supposedly unified these into a single theme-driven setting, but the build still exposes them independently (or the single setting doesn't propagate). Verify which commit *actually* landed the consolidation; confirm the Settings UI now reads from one source of truth and that both surfaces subscribe to it.

## Polish (later)

- [ ] **10. Waveform decay** — not-now; revisit once core bugs are cleared. Tune falloff on the pill waveform so bars don't snap to zero.
- [ ] **11. Hold-hotkey mode bar visuals** — needs a pass for spacing / contrast / motion; capture specifics when we get here.

## Architecture / Refactor (follow-up to #5a)

- [ ] **19. Central `KeyEventRouter` — consolidate scattered hotkey / key monitors.** Today keyboard listening is fragmented across `GlobalHotkeyMonitor` (⌥+/ tap/hold/double-tap), `EscapeKeyMonitor` (plain Esc → pill cancel), `HotkeyRecorder` (Settings > Shortcuts capture UI), and ad-hoc `NSEvent.addLocalMonitorForEvents` callers. Each owns its own lifecycle, install/teardown, and swallow logic. After #5a-v1 lands, #5a-v1 adds a *fourth* seam (a standalone `HotkeyEventTap` class backing only `GlobalHotkeyMonitor`). This backlog entry is the planned **5a-v2** follow-up: introduce a single `KeyEventRouter` that owns the CGEventTap + NSEvent local monitor pair and exposes a subscription API; migrate `EscapeKeyMonitor`, `HotkeyRecorder`, and any ad-hoc callers to subscribe through the router. Scope ≈ 3–5 commits, dedicated planning pass required before coding.
  - Dependency: #5a-v1 must ship first so the `HotkeyEventTap` class exists as the starting point.
  - Guiding principle: consolidation should not be bundled into the bug fix — doing them together risks hiding the #5a behavior change under a big rewrite.

---

## Notes for triage

- Items **1, 4, 5, 9, 12** are the ship-blockers for the current dogfood loop — nothing else matters if the hotkey doesn't work or Esc commits the transcript.
- Item **5** and item **12** both live in the recording-lifecycle state machine; likely one fix stream.
- Item **7** needs a commit-log audit before code changes — confirm what actually merged.
- Each fix should come with a manual-verification line appended to the relevant `Tests/*/Manual*Verification.md` runbook, per project TDD policy.
