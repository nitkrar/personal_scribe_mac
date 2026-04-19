# Seshat — Backlog

## Status

**Phase 1 gate met.** Record → transcribe → paste → persist loop is shipped and dogfooded. Transcript history lands in `~/Library/Application Support/Seshat/recordings/transcripts.jsonl`. Phase 2 = unified architecture + visual identity (see `plans/PLAN_PHASES.md` and `plans/seshat_agent_bundle/`).

## Completed Explorations

| Task | Output Files | Key Findings |
|---|---|---|
| Deep-dive mariov96/scribe | `explorations/scribe_claude.md`, `explorations/scribe_codex.md` | Learning/memory patterns, correction tracking via in-app editor |
| Deep-dive open-wispr | `explorations/openwispr_claude.md`, `explorations/openwispr_codex.md` | SPM build structure, menu bar states, Homebrew distribution |
| Deep-dive VoiceInk | `explorations/voiceink_claude.md`, `explorations/voiceink_codex.md` | Uses FluidAudio/Parakeet, Power Mode, mature app patterns |
| Memory/learning feasibility | `explorations/memory_learning_research.md`, `explorations/memory_learning_codex.md` | NLEmbedding sufficient for personal-scale; dictionary + rules handle most "smart" features |

## Phase 1 — closures

Plan at `plans/PLAN_PHASES.md`. All 15 planned steps + 1.14 reconciliation + 1.15 dogfood landed.

| BACKLOG ID | Closure source | Note |
|---|---|---|
| P0 #1 (app unresponsive at launch) | Steps 1.1 + 1.1b + 1.3a | `Task.detached` in `1cb665c`; signposts instrument prepare path (commit `0969f59` round-out). Cold-launch `prepareTranscriber` measured 730-750ms (gate target < 5s). |
| P0 #2 (download hijacks recording pill) | Commit `1cb665c` | Pre-landed by Codex in `Sources/SeshatAppKit/Overlay/PillOverlayViewModel.swift:26-36` (recording state wins). |
| P0 #5 (pill + menu bar clicks dead) | `1cb665c` + Steps 1.3, 1.3b, 1.4b | Pill: `DraggablePanel.mouseDown/mouseUp`. Menu bar: AppStartupCoordinator extraction removed blocking work from `SeshatAppMain.init` — `Task.yield()` theory was wrong; vestigial wrapper removed in Phase 1 round-out. User runtime-verified on dogfood build (~17 session interactions, no misses). |
| P1 #3 (every rebuild re-downloads 400MB) | Commit `1cb665c` | Pre-landed in `Sources/SeshatTranscription/FluidAudioTranscriber.swift:220-251` (only staging dir wiped on failure). |
| P1 #8 (idle pill draggable) | Commit `1cb665c` | Pre-landed — single `DraggablePanel` reused across all visibility states. |
| P1 #4 (idle dot visual) | Deferred → Phase 2 | Bundle v3 mockup prescribes the new visual per `plans/seshat_agent_bundle/01_Foundations/assets/logo_animation_states.png` and `.../PillOverlayWindow/architecture.png` (Mode 1). |
| P1 #9 (recording pill too big) | Deferred → Phase 2 | Mockup prescribes 180×34 per `.../PillOverlayWindow/command_mode_states.png`. |
| P2 #6 (pulsing-dots animation) | Deferred → Phase 2 | Mockup prescribes animated waveform per `.../PillOverlayWindow/recording_states.png` + `logo_animation_states.png` ("Listening"/"Transcribing" tiles). |
| P3 #7 (LSUIElement emergency quit) | Deferred → Phase 3 | No mockup coverage; gated behind Shortcuts tab in `settings_modes.png`. |

## Phase 1 — new infra shipped (beyond BACKLOG closures)

Beyond the bug-list closures above, Phase 1 also landed:

- **`ModelRegistry` + configurable base dir** (steps 1.5 + 1.6 + 1.7). `SESHAT_BASE_DIR` env var and `SeshatBaseDirectoryPath` UserDefaults redirect the entire state tree; `ModelDescriptor` replaces hardcoded `ParakeetArtifact`. Unblocks multi-model / user-visible storage in Phase 3+.
- **Input Monitoring permission detection** (step 1.9). `IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)` in `SeshatCore/PermissionStatus.swift`; `GlobalHotkeyMonitor` logs a contextual warning if `NSEvent.addGlobalMonitorForEvents` returns nil. Backend only — visible UX lands in Phase 2 NSMenu.
- **`TranscriptStore` actor** (step 1.11 + 1.12). JSONL persistence at `<base>/recordings/transcripts.jsonl` + 500-entry in-memory ring. `SessionCoordinator` writes through on every successful transcription. MenuBarSceneModel is NOT a store observer per bundle v3 BUG-06; NotesWindow in Phase 3 will be the read surface.
- **Build info caption** (step 1.13). `Seshat x.y.z · <git-sha>` footer in the menu bar popover. `package-dev-app.sh` writes HEAD SHA into `Info.plist` at package time.

## Phase 1 — dogfood log (2026-04-18)

Build: `0969f59` (Phase 1 round-out). DMG installed to `/Applications/Seshat.app`.

| Observation | Classification | Next step |
|---|---|---|
| Cold-launch `prepareTranscriber` signpost: 730-750ms first run, ~450ms subsequent | Gate #7 pass — under 5s target | Numbers logged in `Tests/SeshatTranscriptionTests/ManualTranscriptionVerification.md` |
| 17 transcriptions in single session, `transcripts.jsonl` line count matches | Gate #2 pass — ≥10 required | — |
| `log stream` shows zero error-level messages during session | Gate #3 pass | — |
| ~17 menu-bar-ish interactions with no click misses reported | Gate #4 pass (implicit) | — |
| Build caption renders `Seshat 0.1.0 · <sha>` in popover footer | — | — |
| Mic permission re-prompted on install to `/Applications` | Expected (TCC ad-hoc path quirk — each install path has its own TCC record) | No fix; documented in memory |
| Accessibility permission prompt fires at **first paste attempt**, not before recording | Friction — interrupts the first usage flow | **Phase 2:** move the Accessibility prompt to first-record (or an onboarding step before the first session). Consistent with Phase 2 NSMenu + onboarding surface. |

## Phase 2 → Phase 3 hand-offs

Items in original Phase 2 scope that graduated to Phase 3 per `plans/PLAN_PHASES.md`:
- Onboarding window + early Accessibility permission request.
- Settings window (Modes tab, base directory picker, visibility toggles, hotkey customization).

In-Phase-2 items (visual identity, pill redesign, NSMenu rebuild, permission surfacing) closed in Sprint 1 + Sprint 2 — see sections below.

## Phase 2 Sprint 1 — closures (2026-04-18)

Sprint 1 (foundation components + state/audio plumbing) merged on `phase-2`. **254 tests green** (Phase 1 baseline 172 + 82 new). Execution model: 2 parallel Claude implementers in isolated worktrees + 2 Codex reviewers (`codex-cc:codex-rescue`) triggered per-completion; reviewers fixed mechanical issues in place and flagged design divergences.

| Deliverable | Lane / merge | Notes |
|---|---|---|
| `SeshatTheme` (dark + light palettes, typography, spacing, radii; `Palette.for(scheme:)`) | A1 / `bc8e776` | Review `d800a05` corrected dark `appBackground` to `0E0E14` + centralized component metrics. `Color(hex:` outside theme = 0 hits. |
| `SeshatLogoView` (quill with idle/listening/transcribing/error states) | A1 | Stylised SwiftUI vector; revisit at `.icns` export — see TODOs. |
| `WaveformView` (audio-level meter) | A1 | `TimelineView(.animation)` ONLY when `isActive` (kickoff decision locked). No smoothing at this layer. |
| `StatusPill` / `TagChip` / `ActionButton` | A1 | `StatusPill` scope: Settings + Onboarding only — never menu bar, never pill overlay. |
| Asset catalog + `.process("Resources")` in `Package.swift` | A1 | `StatusBarIcon` PNGs are placeholders — see TODOs. |
| `IntentClassifier` protocol + `NoOpIntentClassifier` stub | A2 / `baae506` | Phase 4 placeholder, Sendable-clean; protocol swap point for NLEmbedding / llama.cpp. |
| `AudioLevelCalculator` + `AVAudioCaptureService` RMS stream @ 10 Hz | A2 | Buffer-cadence-driven (no `Timer.scheduledTimer`, no MainActor dep). -60 dBFS floor, 1.0 ceiling. |
| `SessionCoordinator.audioLevelStream()` / `audioLevel()` | A2 | Mirrors `stateStream()` pattern. No new `AppState` type (plan line 279). Review `b359d2c`: fake level stream terminates on error. |
| `@MainActor` on `ActionButtonTests` (test-fix) | Post-merge / `4192e7c` | Swift 6 strict concurrency required it. |

## Phase 2 Sprint 1 — TODOs

- ~~**StatusBarIcon — replace placeholder PNGs.**~~ **Done `5250cca`** (`phase-2 step 2.7b`). Manus export swapped in: transparent monochrome quill silhouette, 18×18 @1x + 36×36 @2x.
- ~~**Trailing `0.0` on `audioLevelStream()` at stop — UI-layer decay in Sprint 2.**~~ **Done `9d7b413`** (`phase-2 step 2.B1c`). `SeshatWaveformDecayMode` UserDefaults enum (`.immediate` default, `.animated` = 500ms linear interpolation) gates `WaveformView` coast-down behaviour. Both modes are runnable dogfood settings.
- **Pixel-fidelity of `SeshatLogoView`** — current SwiftUI `QuillShape` is a stylised vector approximation, not a faithful trace of `plans/seshat_agent_bundle/01_Foundations/assets/logo_dark.png`. Revisit when exporting the `.icns` app icon (plan line 349) so SwiftUI view + icon share a common source.

## Phase 2 Sprint 2 — closures (2026-04-18)

Sprint 2 merged on `phase-2`. **339 tests green** (Sprint 1 baseline 254 + Sprint 2 net 85: +87 new − 2 deleted view-model tests whose surfaces are gone). Execution model: two parallel Claude implementer agents in isolated worktrees (B1 pill, B2 composites), two Codex reviewers per lane, B3 NSMenu rewrite done in main session (worktree path conflicts with Santa / AMFI). B1's Santa popup-storm on worktree xctest execution is the concrete why behind the revised `seshat/CLAUDE.md` "use `swift build --build-tests` in worktrees" rule.

| Deliverable | Lane / merge | Notes |
|---|---|---|
| `ResponseCard` (temporary Command-Mode overlay stub) | B1a / `6f467dd` | Stateless; title + message; champagne palette. Phase 4 consumer. Renamed param `body → message` in `4c8bee0` (SwiftUI `View.body` conflict). |
| `PillVisibilityMode` + `SeshatPillVisibilityMode` UserDefaults (`"auto-show"` default) | B1b / `db806c5` | 3 modes: `.alwaysOn` / `.autoShow` / `.hidden`. Settings UI for toggling lands Phase 3. Invariant (pill + status item can't both be hidden) not yet enforced — trivially holds while Phase 2 status item is always visible. |
| `WaveformDecayMode` + coast-down in `WaveformView` | B1c / `9d7b413` | `SeshatWaveformDecayMode` UserDefaults (`.immediate` default, `.animated` = 500ms linear). `WaveformView` public API preserved (new overload added). |
| Pill overlay rewrite (`PillOverlayView/Presenter/ViewModel/Controller`) | B1d / `ecd3fde` | 180×34 recording pill, animated waveform, champagne palette, three visibility modes. `PulsingDot` deleted per plan line 291. |
| `TranscriptRow` composite | B2a / `dc77f4d` | Phase 3 consumer (`HistoryPanel` + `NotesSidebar`). Title cap 60 chars; 2-line body truncate; timestamp right-aligned. Renamed param `body → preview` in `4c8bee0`. |
| `ModeCard` composite | B2b / `a6f8594` | Phase 3 consumer (Settings Modes tab). Subtitle `"Voice: X · AI: Y"`. Imports `StatusPill`. |
| `AudioPlayerThumbnail` composite | B2c / `36b8d6f` | Phase 3 consumer (Notes Context Panel). 16 bars × 20pt; `h:mm:ss` ≥1h. Imports `WaveformView`. |
| `@MainActor` on composite test classes (B2 review fix) | B2 review / `a632c45` | Swift 6 strict concurrency on SwiftUI `View` test scaffolding. Same mechanical fix as Sprint 1 `4192e7c`. Identified by Codex reviewer pass. |
| `StatusItemMenuModel` pure model + 12 tests | B3a / `bbd492c` | Per `03_Surfaces/MenuBarMenu/IMPORTANT.md`: Quick Memo header / Start Recording ⌥⌘ / History / Settings / Quit Seshat. Permission warnings (Mic + IM) prepend when denied. |
| `StatusItemController` — NSStatusItem + NSMenu owner | B3b / `3dd3180` | Native AppKit class. Tints status-item icon `.systemRed` during recording (single-asset fallback — frame-swap animation needs a second asset). `isolated deinit` cleans up status item under Swift 6. |
| `SeshatAppMain` rewire: `MenuBarExtra` → `Settings { EmptyView() }` + `StatusItemController` | B3c-1 / `bb79fe8` | Scene body is no-op; status item lives outside SwiftUI. Zero SwiftUI inside the menu bar, per IMPORTANT.md. |
| Delete SwiftUI popover dead code | B3c-2 / `70d8f6d` | `MenuBarScene`, `MenuBarStatusIcon`, `RecordButtonView`, `RecordButtonViewModel` + their tests + `recordButton` / `statusIcon` / `preparationStatusText` on `MenuBarSceneModel`. |
| `scripts/package.sh` — flag-driven packaging script | Meta / `26915c8` | Consolidates old `package-dev-app.sh` + `package-dev-dmg.sh` behind `-c/-i/-d/-r`. Always rebuilds fresh (prevents stale-binary trap). `-i` replaces `/Applications/Seshat.app` at a stable path to preserve per-path TCC grants across rebuilds. `-d` keeps the DMG flow for future GitHub Release uploads. |

## Phase 2 Sprint 2 — TODOs

- ~~**Status item icon frame-swap animation.**~~ **Done 2026-04-18 (`853696d`)** — `StatusBarIconListening.png` + `@2x` shipped. `StatusItemController.updateStatusItemAppearance(for:)` swaps between idle / listening poses on recording / transcribing. Pose-swap only, no cross-fade; fine for dogfood.
- **macOS 15 URL-scheme branching for permission deep-links** — *fix if it breaks*. `StatusItemController` uses the macOS 14 anchor (`Privacy_Microphone`, `Privacy_ListenEvent`) which still works on macOS 15. Branch with `if #available(macOS 15, *)` only if Apple renames the anchor in a future point release.
- **`MenuBarSceneModel` rename.** The type no longer backs a "Scene" (no SwiftUI scene anymore); it publishes app state for both pill + status item. Cleaner name: `AppStateModel`. Deferred to Phase 3 to avoid mid-sprint churn. Low blast radius — `StateObject` ownership in `SeshatAppMain` + `SeshatApp`.
- ~~**`.icns` app icon.**~~ **Done `41bb6eb`** — hand-authored RGBA `AppIcon.icns` shipped at `Sources/SeshatAppKit/Resources/AppIcon.icns`.
- ~~**`SeshatLogoView` pixel-fidelity trace.**~~ **Done `5c5d962` (2026-04-18)** — SVG-traced `QuillShape` (vtracer spline trace of master logo PNG at 2048×2048, checked in at `plans/seshat_agent_bundle/01_Foundations/assets/seshat_quill.svg`) replaced the stylised hand-coded path. API simplified to `SeshatLogoView(color:)`. Pill idle pill renders the new silhouette at 14×14. Export-format note: the vtracer output wrote raw-string delimiters backwards (`Z#"` instead of `Z"#`); auto-fixed on import, flag next time.
- ~~**Stable signing identity (`Nitkrar Dev`).**~~ **Done `853696d` (script) + login-keychain cert (2026-04-18)** — `scripts/package.sh` prefers `Nitkrar Dev` when present in login Keychain (TCC permissions persist across rebuilds), falls back to ad-hoc with an echo otherwise. Per-machine setup: Keychain Access → Certificate Assistant → Create a Certificate… → name `Nitkrar Dev`, Identity Type `Self Signed Root`, Certificate Type `Code Signing`, login keychain. Verify: `security find-identity -v -p codesigning | grep "Nitkrar Dev"`. Cert + private key confirmed on primary Mac 2026-04-18 via "My Certificates" tab.

## Phase 2 Sprint 2 — dogfood fixes (2026-04-18)

User-reported dogfood bugs after first `scripts/package.sh -ir` test-drive on 2026-04-18.

| # | Bug | Status | Commit(s) |
|---|---|---|---|
| 1 | App icon missing in Finder / Applications | **Fixed** | `addb1ea` (sips/iconutil autogen) → `41bb6eb` (replaced with hand-authored RGBA icns — source was RGB-only, rendered as flat dark square) |
| 2 | TCC permissions reset on every install; Accessibility asked at paste time not record time | **Parked** | Signing identity stability needed for TCC (ad-hoc CD hash changes per build). Accessibility timing is a known Phase 1 dogfood friction. User asked to follow up later. |
| 3 | Menu bar shows "S" fallback, not quill icon | **Fixed** | `60082ab` (load via `Bundle.module` — SwiftPM doesn't search `Bundle.main`) → `1d1e63b` (flatten asset catalog to direct PNGs — SwiftPM's `.process` doesn't run `actool`, so no `.car` → no `image(forResource:)` lookup). New `StatusItemIconLoader` with manual @2x representation merge + new `ManualStatusItemVerification.md` runbook. |
| 4 | Pill not visible by default or during recording; briefly appears at stop | **Fixed** | Diagnostic log (`6b526bf`) revealed `@Published` emits in willSet → `show()` was reading stale `model.visibility` via a guard and redirecting legitimate show-requests back to `hide()`. Guard removed in `9b97ee4`. Sink dispatches `.hidden` → `hide()` separately, so `show()` can trust that it's only called when visibility is non-hidden. |
| 5 | Menu advertises Cmd-something shortcut; actual hotkey is double-tap right Option | **Fixed** | `e628d31` — removed AppKit keyEquivalent (NSMenu can't represent a double-tap), appended `⌥⌥` hint to the title text: `"Start Recording   ⌥⌥"` / `"Stop Recording   ⌥⌥"`. Test `testStartRecordingHasNoAppKitKeyEquivalent` guards against re-introducing the phantom shortcut. |
| 6 | Status bar icon shows a block background instead of a silhouette | **Fixed** | Two passes: `86b6663` flood-filled the Manus PNG alpha to extract the carved-quill interior (the original asset was inverted — block opaque, quill carved out as transparent). `853696d` later received a proper monochrome silhouette + listening-pose asset from Manus and swapped those in. |
| 7 | Fuzzy / hairy border around pill — system NSPanel shadow bleeding past the rounded corners | **Fixed** | `9483ffa` — `NSPanel.hasShadow = false` on the pill + ResponseCard panels; SwiftUI chrome applies `.clipShape(RoundedRectangle)` BEFORE `.shadow(...)` so the shadow composites on a clean edge. Same fix preemptively applied to `ResponseCard` NSPanel for Phase-4 readiness. |
| 8 | `swift test` polluted the live clipboard + fired real Cmd+V into the focused app; real `DraggablePanel.show()` briefly flashed on screen | **Fixed** | Codex-implemented + Claude-reviewed test sandbox (`d10dd4e` / `da776ac` / `d87ad24`): new protocols `PillOverlayPaneling`, `PillOverlayPanelBuilding`, `PasteInjecting`; tests use `RecordingPanelBuilder` / `SilentPaster` / `NoOpPanelBuilder` fakes; `PasteInjector.live(...)` seam takes a named `NSPasteboard(name: "seshat.test.<UUID>")` + no-op CGEvent poster. 340 tests preserved, zero real-side-effect paths remaining (reviewer grep audit 2026-04-18). |
| 9 | Initial hotkey silent after fresh install until user manually clicks menu bar | **Open** | Hypothesis: `NSEvent.addGlobalMonitorForEvents` returns nil on launch if Input Monitoring isn't granted yet; menu-bar click causes app-activation which flushes the TCC state. Proposed fix: hook `NSApplication.didBecomeActiveNotification` to re-probe + re-install `GlobalHotkeyMonitor` on activation. Not yet shipped — waiting on repro confirmation after the `Nitkrar Dev` signing takes effect (stable signature may already make the permission stick). |

## Deferred to Phase 3+ (not forgotten)

- **Personal dictionary — ship in two stages.** (Renamed from "Personal dictionary + prompt injection": prompt injection is Whisper-specific. Parakeet uses decoder-level custom-vocab instead — see `.build/checkouts/FluidAudio/Documentation/ASR/CustomVocabulary.md`.)
  - _Stage A (minimum):_ refactor `Sources/SeshatCore/PostProcessor.swift` from single `clean()` to a chain-of-stages (preserve public API; current 2 stages become `FillerRemovalStage` + `BasicPunctuationStage`). Add `PersonalDictionaryStage` applied **first** in the chain (before filler removal, so corrections run on raw ASR output). Data model: 1:many — `struct DictionaryEntry { term: String, alternatives: [String], createdAt: Date, source: EntrySource }`. Storage: JSON at `<SeshatConfig.baseDirectory()>/dictionary.json`. Match: case-insensitive word-boundary replacement of each alternative → term; in-order iteration, first match wins per region. No regex (YAGNI). No frequency/starred/context fields at Stage A — those power Stage B. No UI — manual entry via file edit; Settings UI Phase 3. Soft ceiling guidance: ~40 entries / 60-char limit per entry (Wispr Flow reference).
  - _Stage B:_ decoder-level biasing via Parakeet CTC custom-vocab head (backend-specific; whisper.cpp path would use `initial_prompt` instead). Correction learning loop — diff user-edited transcript vs original via `CollectionDifference`, pair removals with nearby insertions, filter by Levenshtein distance. Depends on Phase 3 `NotesWindow` edit UI. Add frequency + decay ranking if Stage B pursues biasing (top-30 terms by decayed frequency feed the CTC vocab / prompt).
  - _Phase 4 (separate future item, NOT this row):_ Apple Foundation Models post-processing correction (macOS 26+). LLM takes raw transcription + dictionary as prompt context, returns corrected text. Different tier.
  - _Reference:_ `explorations/memory_learning_research.md` lines 274–444 have the full data model, prompt builder, post-processing engine, and correction-learning algorithm. Don't re-derive.
- Correction tracking / auto-learning
- Time-saved analytics
- Voice tags, micro-prompts
- **VAD auto-stop — ship in two stages.**
  - _Stage A (minimum, 1–2 commits):_ plumb FluidAudio `VadManager` into `AVAudioCaptureService` → `SessionCoordinator`. Two states only (`Recording`, `Quiet`). After **2.5s continuous Quiet** (VAD probability < 0.3), fire stop. **No UI change** — the pill's waveform flattens naturally when audio is quiet; that is the signal. Hard-coded threshold + duration, no Settings UI. Manual hotkey stop always wins in any state.
  - _Stage B (only if Stage A actually feels jarring in daily dogfood):_ add `About-to-stop` sub-state with subtle tint + `"…stopping"` text + ~0.8s grace window before fire. Threshold configurable behind `SettingsWindow` (Phase 3 anyway). Couples to Phase 2 pill design system; don't start until Stage A has ≥1 week of dogfood and a specific friction is observed.
  - _Scope-discipline rationale:_ don't design Stage B before Stage A tells you it's needed. The natural waveform-flatten may already be enough signal; designing a grace-window UI before feeling the MVP in daily use is the creep trap.
- **Auto-pause playback during recording.**
  - _Stage A (minimum):_ on `SessionCoordinator.start()`, read `UserDefaults.standard.bool(forKey: "SeshatAutoPausePlayback")` (default **true**). If enabled, call `MPRemoteCommandCenter.shared().pauseCommand` to send a system-wide pause to the active media-playing app (Netflix, Spotify, YouTube, Music.app). No auto-resume — user chose to pause, they can hit play when done. No Settings UI; users can flip via `defaults write com.nitkrar.seshat SeshatAutoPausePlayback -bool false` until Settings ships. Follows the same UserDefaults-now / Settings-UI-later pattern used for `SeshatPillVisibilityMode` (plan line 293) and `SeshatWaveformDecayMode`.
  - _Stage B (ships with `SettingsWindow` in Phase 3):_ Settings toggle bound to the same UserDefaults key. Optional opt-in auto-resume after session ends.
  - _Interaction with future meeting mode:_ meeting mode (dual-track recording) needs system audio playing — disable auto-pause when meeting mode is the active mode regardless of the toggle.
  - _Default choice (`true`):_ dictation's default case is "leak hurts transcription quality"; protect-by-default. Power users who want music + dictation can flip the flag.
- 7-stage post-processing pipeline
- Smart auto-archive
- Full clipboard save/restore (all pasteboard types)
- **Active window context capture — ship in two stages.**
  - _Stage A (minimum):_ new `RecordingContext` struct in `SeshatCore` (`bundleIdentifier: String?`, `appName: String?`, `capturedAt: Date`). Add optional `context` field to `TranscriptEntry` (Codable optional handles JSONL backward-compat automatically — older entries decode `nil`, no migration). At hotkey-press time (mirror `PasteInjector`'s capture-before-Seshat-gains-focus pattern), read `NSWorkspace.shared.frontmostApplication` via a `FrontmostAppProviding` protocol for testability. Pass through `SessionCoordinator.start()` to the entry written on completion. **No UI, no consumer feature yet — persist metadata only.** No new permissions needed (NSWorkspace is free). Unknown context (menu-bar-triggered sessions where Seshat itself is frontmost) is a valid `nil`; don't force a value.
  - _Stage B (when a consumer feature actually needs it):_ opt-in window title capture via AX (already have permission); opt-in browser URL via per-browser AppleScript/ScriptingBridge; surface in Phase 3 `NotesWindow` as filter chips; enables the parked `App-context rules for mode selection` (see FluidAudio feature map). Window titles + URLs are privacy-sensitive — explicit opt-in, never at Stage A.
  - _Rationale:_ cheap to capture now, valuable substrate for future mode-selection rules / smart routing / search. Bundle ID + app name is low-sensitivity (Dock-visible); data stays local, never pulled.
- **Me-vs-other speaker verification — ship in two stages.** (Sub-feature of deferred Notes-pillar multi-speaker work; standalone because the primitive is ASR-agnostic and has no Meeting Mode dependency.)
  - _Stage A (minimum):_ one-time voiceprint enrollment via a menu bar item ("Enroll my voice…" — captures ~30s, runs through FluidAudio `DiarizerManager`, persists `Speaker` JSON to `<SeshatConfig.baseDirectory()>/speaker_voiceprint.json`). On `SessionCoordinator` stop, if recording duration ≥ `SeshatSpeakerVerificationMinDuration` (default **120s**, flip via `defaults write`) AND a voiceprint exists, show a post-stop prompt **before** Parakeet fires: *"Tag speakers for this recording?"*. If yes, run `DiarizerManager.performCompleteDiarization(audio)` in parallel with Parakeet; pre-init speaker manager with enrolled voiceprint via `initializeKnownSpeakers([me])`; relabel matched cluster → `"me"`, all other clusters → `"other"`. Add optional `speaker: "me" | "other"` field to each `TranscriptEntry` segment (Codable optional, JSONL backward-compat). No Settings UI. Feature gate `SeshatSpeakerVerificationEnabled` — default `true` once voiceprint exists, `false` otherwise (so the prompt is invisible before enrollment). Parakeet + diarizer run in parallel → total wait ≈ max(Parakeet, diarizer), not sum. No consumer UI for the tag — persist only; NotesWindow (Phase 3) will surface.
  - _Stage B (dogfood-gated):_ Settings UI for threshold, enable/disable, re-enrollment. "Don't ask again for this recording" dismissal policy. Low-confidence-match warning when no match is strong (stale voiceprint, noisy audio). Feeds future Meeting Mode — Meeting Mode supplies its own richer `me / Alice / Bob` shape; me-vs-other becomes the fallback when Meeting Mode is off.
  - _Scope-discipline — NOT in Stage A:_ real-time / streaming diarization, N-speaker labels beyond me/other, cross-session recognition for non-me speakers, app-context-based gating (separate backlog item).
  - _Open unknowns to resolve before starting Stage A:_ (a) exact Pyannote pipeline model size on disk + peak RAM (measure by downloading `FluidInference/speaker-diarization-coreml` once); (b) whether default `speakerThreshold: 0.65` is strict enough for reliable me-vs-other, or needs lowering; (c) UX for "you need to enroll first" guidance if user tries to opt-in without a voiceprint.
  - _Rationale — duration gating:_ 80%+ of dictation sessions are short solo memos where speaker tags are noise. Duration is a cheap ASR-agnostic signal that doesn't depend on Active-window context infra. Post-stop prompt preserves user consent on the added RAM hit.
- SQLite note storage via GRDB.swift with FTS5 search (imports from existing JSONL — Phase 3)

## FluidAudio feature map — post-current-phase pickup

Captured from FluidAudio README + showcase-app review on 2026-04-18. All items assume current Phase 2 visual/architecture work lands first. No fixed priority within this list; order depends on dogfood feedback.

**English-only, ASR-first scope:** translation and MT models are parked until after core features land.

### Net-new — not yet listed elsewhere

| Item | Pillar | Notes |
|---|---|---|
| Streaming dictation mode (EOU partials + v3 final) | Dictation | Separate hotkey from quick mode. EOU 120M partials render in overlay pill only (no paste during streaming); v3 batch re-transcribes on stop to produce the pasted final text. ~850MB ANE footprint while active. English-only. |
| App-context rules for mode selection | Dictation | Frontmost-app rules (`Notes/Word/Pages → long-form`, `Slack/iMessage → quick`). Not a FluidAudio feature; depends on streaming mode shipping first. |
| Speaker diarization (LS-EEND default) | Notes | FluidAudio LS-EEND: 10 speakers max, 100ms streaming updates, single model. Sortformer optional (4 speakers, stronger identity, NVIDIA Open Model License). |
| Dual-track recording (mic + system audio separately) | Notes | `ScreenCaptureKit` audio tap (macOS 13+). Mic track = "me" trivially; diarize only the system-audio track. Precondition for meeting mode. NOT what current mic-only capture does — Seshat today mixes speaker leakage into the single mic stream. |
| Cross-session speaker recognition | Notes | Pyannote WeSpeaker embeddings + local speaker DB; pre-enrollment flow. Only the Pyannote pipeline supports this reliably. |
| Meeting mode | Notes | Zoom/Teams/Webex auto-detect + dual-track + diarization + cross-session IDs. Composes the three rows above. |
| TTS for assistant speaking back (Kokoro + PocketTTS) | Assistant | Kokoro 82M parallel (SSML, pronunciation control) + PocketTTS streaming with voice cloning. English-only initially. |
| MCP server exposing transcripts | Assistant | **Wishlist — build only on actual demand.** When needed, Stage A shape: standalone stdio binary (~200-300 LOC SPM executable target) that reads `transcripts.jsonl` from `SeshatConfig.recordingsDirectory()` and exposes read-only tools `search_transcripts` / `list_recent_transcripts` / `get_transcript`. No in-app HTTP server unless Stage A proves insufficient. JSONL is already mode 600; document privacy caveat at opt-in time. Swift MCP SDK if mature, else hand-rolled JSON-RPC. |

### Cross-refs — already captured elsewhere, don't re-add

- **VAD auto-stop** → existing `VAD auto-stop tuning, configurable timeout` (Deferred to Phase 3+).
- **Inverse Text Normalization (ITN)** → one stage inside existing `7-stage post-processing pipeline` (Deferred to Phase 3+).
- **Custom vocabulary / personal dictionary** → existing `Personal dictionary` entry (Deferred to Phase 3+). Stage B decoder-level biasing there covers FluidAudio's `CustomVocabulary.md` + `CustomPronunciation.md` mechanisms.
- **Non-English ASR** → existing `whisper.cpp integration for non-English` (Future). Parakeet v3 already covers 25 European languages as an alternative.
- **LLM summaries / action items / mindmaps** → existing `LLM assistant features` (Future). Covers Talat/OpenOats-style notes-pillar features.

### Explicitly parked

- **Real-time translation (source → non-source target)** — revisit based on performance; needs separate MT model (NLLB-200 or M2M-100, ~1.2GB quantized).
- **Nemotron streaming ASR** — NVIDIA licensing more restrictive than Parakeet's Apache 2.0; no compelling reason to adopt.
- **Qwen3-ASR** — redundant with Parakeet.
- **Duration-based dictation-mode escalation** — UX-awkward; revisit only if explicit streaming hotkey feels insufficient.

## Future (not yet scoped)

- [ ] Landing page / website (before public launch)
- [ ] Homebrew distribution
- [ ] Accessibility audit
- [ ] Data-at-rest encryption (SQLCipher)
- [ ] whisper.cpp integration for non-English
- [ ] LLM assistant features
- [ ] Mouse side-button trigger (4th/5th button via event-tap extension to `GlobalHotkeyMonitor`). Low-effort power-user feature for Logitech MX / gaming-mouse workflows. Skip trackpad gestures + Force Touch — they conflict with macOS system gestures.

## Project Files Index

| File | Purpose |
|---|---|
| `PROPOSAL.md` | Direction and architecture (v3, post-engine-switch) |
| `DECISIONS.md` | Decision log + hypotheses + rejected alternatives |
| `COMPETITIVE.md` | Competitive landscape comparison |
| `BACKLOG.md` | This file |
| `REVIEW.md` | Technical architecture review |
| `ASSISTANT_FEASIBILITY_REVIEW.md` | ML feasibility review (Claude) |
| `CODEX_ML_REVIEW.md` | ML feasibility second opinion (Codex) |
| `REVIEW_SYNTHESIS.md` | Consolidated findings from 6 reviewers |
| `explorations/` | Deep-dive outputs (8 files) |
