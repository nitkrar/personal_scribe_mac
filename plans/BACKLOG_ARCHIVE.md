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
