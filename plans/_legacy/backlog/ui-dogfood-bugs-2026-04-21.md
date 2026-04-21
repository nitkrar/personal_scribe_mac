# UI Dogfood Bugs — 2026-04-21

User-reported issues from a dogfood build of Ninimma. Captured verbatim as a punch list; triage / root-cause / fix commits come later. Each item is a discrete bug-or-polish — do NOT collapse into one mega-commit.

Legend: `[ ]` open · `[~]` in progress · `[x]` fixed (reference commit)

## Critical (blocks usable flow)

- [x] **1. About tab traps navigation.** Opening the About tab disables tab switching — no way to return to Home/other tabs. After About is opened once, subsequent "Open Home" actions still land on About. Likely a tab-state / default-selection bug that latches onto About.
  - **1a FIXED** (`726e538`) — menu-bar "Home" now routes to the Home tab via `showWindow(selecting: .home)`.
  - **1b FIXED** (`1196e73`) — `NavigationSplitView(columnVisibility: .constant(.all), ...)` pins the sidebar; can't auto-collapse via toolbar chevron or content width.
  - **1c FIXED** (`cd776df`) — About moved out of Settings sub-tabs into a clickable sidebar footer row under the Microphone footer (styled like Microphone, not like the tab rows). New `AppTab.sidebarListCases` excludes `.about` from the regular `List`.
- [x] **4. Global hotkey dies when app window is frontmost.** Switching between full-screen apps and the main desktop (where Ninimma's window is focused) kills the hotkey on the focused space. Hotkey only works when app is NOT in the foreground. Event-tap scope / key-down capture regression. — FIXED (`a12b7e2` + `f3773e6`): added `addLocalMonitorForEvents` alongside the existing global monitor; swallow matching events so `÷` doesn't leak into our own text fields, with a `hotkeyKeyDownSwallowed` flag preventing unbalanced keyUp delivery. The `÷÷÷÷` leak into *other* apps was a separate bug (#5a) — also now fixed.
- [~] **5. Hold-to-record writes `÷÷÷÷÷÷÷` then drops the transcript.** Holding `opt + /` types the `÷` character repeatedly for the duration of the hold and then does NOT paste the transcription. Two sub-bugs originally identified: (a) key-swallow failing on hold; (b) paste-on-release broken.
  - **5a-v1 c1 LANDED** (`fd9d47a`) — `HotkeyEvent` adapter (no-op refactor) + `CGHotkeyEventTapContext.swift` scaffolding in their own files.
  - **5a-v1 c2 LANDED** (`ce6ba19`) — standalone `HotkeyEventTap` class wires `CGEvent.tapCreate` at `.cgSessionEventTap` + `.headInsertEventTap`; swallow matching ⌥+/ keyDown (incl. auto-repeat) + matching-keyCode keyUp system-wide. Stops the `÷÷÷÷` leak into other apps. **Needs runtime verification** via MV-HK-8/9/10/11.
  - **5b.A FIXED** (`4d5bf7f` + `4114614` test fix) — replaced symmetric `coordinator.toggle()` on hold with explicit `startIfIdle` / `stopIfRecording`. Prevents the fallback path where `onHoldRelease` could *start* a recording instead of stopping one.
  - **5b.C deferred** (`231df70`) — pill `collectionBehavior` already has `.canJoinAllSpaces` / `.fullScreenAuxiliary` / `.stationary`. Real cause of the user-reported "pill not visible from full-screen app" symptom is unknown; MV-PUX-17 on trunk points next investigation at `updatePanelPosition(_:)` / `NSScreen.main?.visibleFrame`.
  - **5b paste race** — codex's third theory (synthetic ⌘V racing trailing `÷` keystrokes) is likely moot now that 5a swallows the `÷` events. Confirm at runtime.
  - **#19 follow-up:** central `KeyEventRouter` (5a-v2) consolidation queued after dogfood verification.
- [x] **9. Menu bar "Copy last transcript" is a no-op.** — FIXED: renamed action to "Copy Last Transcript", implementation is now strict copy-to-clipboard via CopyLastTranscriptAction (no paste attempt, no AX branching). Silent no-op on empty history replaced with a logged outcome; a user-visible toast is deferred to a general feedback polish pass.
- [ ] **12. Esc during recording behaves like Stop, not Cancel.** Esc should discard the in-flight recording *without* writing anything to the clipboard. Today it commits whatever was captured so far (same behavior as Stop). See Phase 8 cancel-without-transcribe backlog — this is the user-visible symptom.

## Sidebar

- [ ] **18. Microphone footer label in left pane is inert.** A small "Microphone" label sits at the bottom of the left sidebar but clicking / hovering does nothing — no menu, no picker, no tooltip. Decide intent: should it (a) open a mic picker popover, (b) route to Settings → input device, (c) display the currently selected input as a status readout only, or (d) be removed? Pick one and wire it (or strip the label).

## Menu bar

- [x] **2. Hide "Check for Updates" from menu bar.** — FIXED: removed the stub entry entirely; will be re-added when the updater pipeline ships.
- [x] **6. "Ninimma — dictation" wraps to 2 lines in the menu bar.** — FIXED: merged the brand and mode headers into one row ("<displayName> — <mode>", em-dash separator, falls back to brand-only when no mode is active). Single non-interactive header emission in `StatusItemMenuModel.makeUnified`.
- [x] **16. Add "Settings" and "History" entries to the menu bar.** — FIXED: added `.openTranscriptions` and `.openSettings` ActionIDs, inserted History (waveform icon) + Settings (gearshape icon) under Home, wired through `showWindow(selecting:)` using the #1a pattern.

## Settings — General

- [ ] **3. "Launch at Login" toggle doesn't trigger the system-settings / permission flow.** Toggling ON silently flips state but never prompts or requests the Login Items permission. Verify `SMAppService` / helper invocation is actually firing.
- [x] **8. "Settings" section label above the tab strip is redundant and wraps on default width.** — FIXED: removed the redundant "Settings" largeTitle above the sub-tab picker in SettingsTab.swift — window chrome + sidebar row already identify this as Settings.
- [x] **14. "Shortcuts" tab has only one row — demote to a subsection inside General.** — FIXED: relocated the Record/stop-dictation row into a Shortcuts subsection at the bottom of the General sub-tab; removed the standalone Shortcuts sub-tab + enum case + ShortcutsTab.swift.

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

- Original ship-blockers were **1, 4, 5, 9, 12**. As of `a77724b` (2026-04-21 afternoon): **1, 4, 9 fully shipped + tests pass**; **5 has all source landed but needs runtime verification** (MV-HK-8..11 in `ManualHotkeyVerification.md`); **12 is the only remaining critical, parked pending Esc-vs-✕ semantic call** (spec-literal-discard vs Esc-as-soft-cancel).
- Item **7** needs a commit-log audit before code changes — confirm what actually merged.
- Each fix should come with a manual-verification line appended to the relevant `Tests/*/Manual*Verification.md` runbook, per project TDD policy.
