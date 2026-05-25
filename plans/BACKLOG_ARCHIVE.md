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

Active follow-ups split off as tickets: **#039** (whisper.cpp dedup tracker — deferred), **#040** (#101 WhisperKit dogfood verification — pending DMG rebuild), **#041** (delete `AppEntryPointTests.testPersonalScribeAppMainBuildsSceneModelFromComposition` skip), **#042** (memory idle-release note — informational, no action).
