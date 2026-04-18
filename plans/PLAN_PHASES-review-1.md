VERDICT: NEEDS_REVISION

## Summary Assessment

The phase structure is sound and correctly scopes Phase 1 to stability-plus-foundational-refactor with all visual/design work deferred to Phase 2. However, the plan misreads the current working tree — Steps 1.1 and 1.2 describe code states that no longer exist because Codex's uncommitted work already landed those fixes — and it leaves the in-flight merge conflict surface under-specified (1.12 touches the same files as 1.1). Several other issues (wrong script name in 1.15, `CGPreflightListenEventAccess` measuring the wrong TCC permission, UserDefaults-domain caveat in 1.6, unverifiable gate in 1.15, ring capacity of 50 too small for a full-day dogfood) block an agent from executing the plan without thinking.

## Critical Issues (must fix — numbered)

### 1. Steps 1.1 and 1.2 are already implemented in the working tree.

`Sources/SeshatSession/SessionCoordinator.swift:155-168` already shows:
```swift
private func prepareTranscriberInBackground() {
    let transcriber = transcriber
    let logger = logger
    Task.detached(priority: .background) { ... }
}
```
That is exactly what Step 1.1 asks to produce. Similarly, `Sources/SeshatAppKit/Composition/AppComposition.swift:54-60` no longer contains `} catch { _ = error }`; the catch at lines 58-60 already calls `logger.error("Startup transcriber preparation failed", error: error)`. The "before" snippet in Step 1.2 does not exist anywhere in `Sources/**/*.swift` (verified via grep).

Both are covered by the uncommitted Codex patch in the working tree (`git status` shows M on both files). An executing agent reading "change `Task {` → `Task.detached {` at line 160" will be confused and may revert Codex's work.

Required fix: reframe Steps 1.1 and 1.2 as "verify-and-commit" rather than "write-and-commit". Keep the mock-transcriber unit test in 1.1 and the `log stream` verification in 1.2 as they are still valuable, but rewrite the preface to say "Codex's in-flight patch already applied the production-code change; commit and add the missing test."

### 2. Group 1 vs Group 2 ordering: uncommitted work touches more files than Step 1.7 acknowledges.

Plan line 148 warns that 1.7 must rebase after Codex merges because of `FluidAudioTranscriber:240`. Correct but incomplete. `git status` shows uncommitted M on:
- `Sources/SeshatAppKit/Composition/AppComposition.swift`
- `Sources/SeshatAppKit/Composition/SeshatAppMain.swift`
- `Sources/SeshatAppKit/MenuBar/MenuBarScene.swift`
- `Sources/SeshatAppKit/MenuBar/MenuBarSceneModel.swift`
- `Sources/SeshatAppKit/Overlay/PillOverlayController.swift`
- `Sources/SeshatAppKit/Overlay/PillOverlayView.swift`
- `Sources/SeshatAppKit/Overlay/PillOverlayViewModel.swift`
- `Sources/SeshatCore/Protocols.swift`
- `Sources/SeshatSession/SessionCoordinator.swift`
- `Sources/SeshatTranscription/FluidAudioTranscriber.swift`

And untracked: `Sources/SeshatAppKit/Composition/AppStartupCoordinator.swift`.

Step 1.12 (plumb TranscriptStore through) modifies `SessionCoordinator.swift`, `AppComposition.swift`, `MenuBarSceneModel.swift` — all three have uncommitted Codex edits. Step 1.4 (pill click tests) touches `PillOverlayPresenter.swift` which Codex has fully rewritten (including `OverlayPanelInteractionState` and the `DraggablePanel`/`ClickThroughHostingView` mouseDown/mouseUp overrides that Step 1.4's tests target). The DAG at line 319-338 treats 1.12 and 1.4 as parallel-safe with Codex handoff; they are not.

Required fix: add an explicit Step 1.0 "Codex handoff integration" — commit the uncommitted work (after diff audit) before starting any numbered Phase 1 step. Update the DAG to gate 1.4 and 1.12 on 1.0.

### 3. Step 1.9: `CGPreflightListenEventAccess` measures the wrong TCC permission.

Plan line 166 proposes `CGPreflightListenEventAccess()` for Input Monitoring detection. That symbol surfaces Accessibility (AX) permission state, not Input Monitoring. `NSEvent.addGlobalMonitorForEvents(matching: .keyDown, ...)` (used by `GlobalHotkeyMonitor`) requires Input Monitoring, which is gated by TCC's `kTCCServiceListenEvent` and surfaced via `IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)` only. The plan will mis-report state: AX granted + Input Monitoring denied will show "granted" incorrectly.

Other issues in the same step:
- `import IOKit.hid` is required; `SeshatCore` does not currently link IOKit.
- The System Settings URL `x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent` changed on macOS 15 — needs `if #available(macOS 15, *)` branching.
- `IOHIDCheckAccess` returns `kIOHIDAccessTypeUnknown` until the app has tried to create an event tap at least once; calling it on first launch before `NSEvent.addGlobalMonitor*` has run will return `.notDetermined`-equivalent.

Required fix: use `IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)` only; import IOKit.hid in the new PermissionStatus.swift; gate detection on "after first monitor attempt"; add the macOS 15 URL branch.

### 4. Step 1.15 references a script that does not exist.

`Scripts/` contains `package-dev-app.sh` and `package-dev-dmg.sh`. There is no `Scripts/package.sh`. An agent executing Step 1.15 literally will fail at the first line.

Required fix: replace with `Scripts/package-dev-dmg.sh` and document any env vars it needs. Also pin the DMG install target — "drag to `/Applications`" should name the known-good path: `/Applications/Seshat.app` (so the dogfood log can correlate with the TCC-ad-hoc-path quirk captured in user memory).

### 5. Step 1.6 UserDefaults semantics are not fully accurate for `swift run`.

Spec (referenced by 1.6) documents the user CLI as `defaults write com.nitkrar.seshat SeshatBaseDirectoryPath …`. That works only once the binary runs from the packaged `.app` with `CFBundleIdentifier = com.nitkrar.seshat`. When developers run via `swift run`, the executable's bundle identifier is the SPM default (typically empty or `SeshatAppKit`) — `UserDefaults.standard` reads the `NSGlobalDomain` chain plus the empty bundle domain, NOT `com.nitkrar.seshat`. So `defaults write com.nitkrar.seshat …` is a silent no-op during local dev.

Separately, under `swift test`, `UserDefaults.standard` uses the xctest host's defaults domain. The planned test "set UserDefaults key, assert baseDirectory() reflects it" will pass trivially because the SAME process reads/writes the same standard domain, but it does not prove the runtime CLI path works.

Required fix:
1. Add a comment in `SeshatConfig` noting the "UserDefaults only takes effect when running the packaged `.app`" caveat.
2. Add `defer { UserDefaults.standard.removeObject(forKey: "SeshatBaseDirectoryPath") }` to the test for isolation.
3. Add a manual verification entry: `defaults write com.nitkrar.seshat SeshatBaseDirectoryPath /tmp/foo; open /Applications/Seshat.app; verify models land under /tmp/foo/models/`.

### 6. Step 1.11 TranscriptStore capacity=50 is undersized for dogfood.

Phase 1 gate explicitly mentions "survives a full-day dogfood session". A user doing short dictation bursts hits 50 entries in ~2 hours. When Phase 3 migrates to SQLite from the in-memory store, only the last 50 entries survive. This quiet eviction defeats the point of keeping history during dogfood.

Required fix: raise capacity to 500 (memory is negligible) or, preferably, add a newline-delimited JSON spillover to `recordingsDirectory()` that Phase 3's SQLite migration can ingest. Either way, log at INFO when eviction starts so the dogfood log can observe it.

### 7. Phase 1 gate "dogfood-log section exists" is unverifiable.

The gate at plan line 240 reads "Manual dogfood-log section exists and has at least one real day recorded." Neither condition is objectively testable.

Required fix: tighten to concrete thresholds, e.g. `≥ 10 transcriptions logged in TranscriptStore during a single app session; no unrecovered crashes in `log stream --predicate 'subsystem == "com.nitkrar.seshat"'`; the menu-bar popover opens on single click every time in a 20-click sanity test; dogfood log records either "≥ 5 specific frictions" or explicit "zero frictions". Phase 2 start requires the committer to add a "Phase 1 gate met: YYYY-MM-DD" line in BACKLOG.md`.

### 8. Step 1.3 (menu bar click diagnosis) violates the 2–5-minute step-sizing rule.

Three distinct investigative actions + three candidate fixes bundled as a single step with a single commit. An executor has license to skip to a guessed fix.

Required fix: split into 1.3a (diagnostic instrumentation — add `log` calls in `GlobalHotkeyMonitor.start` and in the `MenuBarExtra.label` closure; run app; capture `log stream` snippet), 1.3b (apply narrow fix indicated by 1.3a output), 1.3c (regression test in `MenuBarFlowIntegrationTests.swift`). Keep the diagnostic instrumentation in the commit graph so a future regression can reuse it.

### 9. No Signposts / timing measurement for the launch-freeze root-cause.

BACKLOG "next-session starter" item 2 explicitly states: "instrument `SessionCoordinator.prepareTranscriber()` / `FluidAudioTranscriber.performPrepare()` / `inference.loadModel(from:)` with `os.signpost` to find the stall." Plan's Step 1.1 only addresses the actor-reentry theory. If the actual cause is `AsrManager.loadModel` CPU-starving MainActor (BACKLOG's stated hypothesis), Task.detached does not fix it — it just unblocks `stop()` from `prepare()`.

Without signpost instrumentation, the Phase 1 gate "no per-launch freeze" cannot be objectively confirmed.

Required fix: add Step 1.1b — `OSSignposter`-wrap the three methods above, emit `.begin`/`.end` around each, and add a manual verification `xcrun xctrace record --template 'Logging' -l 30` entry so dogfood can cite measured latencies.

### 10. Step 1.14 backlog reconciliation does not attribute pre-landed fixes.

Step 1.14 lists closures for P0 #1, P0 #2, P0 #5, P1 #3, P1 #8. The plan body never tells the implementer which step produces the closure for P0 #2 (download-pill hijack — already fixed in `PillOverlayViewModel.swift:26-36` via the uncommitted Codex patch) and P1 #3 (model re-download — already fixed in `FluidAudioTranscriber.swift:220-251` where `ensureValidDownloadedModel` now removes only the staging dir). An executor walking the BACKLOG cannot tell whether the issues are handled.

Required fix: add a "Pre-landed in Codex handoff" column to the 1.14 reconciliation table. Each BACKLOG row maps to either (a) a Phase-1 step number, (b) the already-landed commit SHA (after Step 1.0 commits the in-flight work), or (c) "explicitly deferred to Phase N.M".

### 11. Phase 1 volume vs. 17-day calendar is overambitious.

Today is 2026-04-18. Dogfood is 2026-05-05. That's 17 calendar days including weekends. Phase 1 has 15 numbered steps + Codex handoff + a full-day dogfood inside the window. Rough sizing:
- 1.3 menu-bar click (unknown RCA): 1-2 days
- 1.5/1.6/1.7 registry refactor: 1-1.5 days
- 1.9 IM permission (with Critical #3 rework): 0.5-1 day
- 1.11-1.13 TranscriptStore: 1 day
- 1.15 dogfood + contingency: 1 day + buffer

That's 4.5–6.5 focused dev-days on top of Codex integration. On a solo builder this likely slips 3-5 days.

Required fix: explicitly tier steps. Tier-A (must ship by dogfood): 1.0, 1.1, 1.3, 1.5-1.8, 1.11-1.13, 1.15. Tier-B (nice-to-ship; ship as log-only if time-pressed): 1.9, 1.10. Tier-C (defer to Phase 2 rollup): 1.14 can be deferred by a day.

## Suggestions (nice to have)

### 1. Add an explicit Step 1.0 "Verify and commit Codex handoff"

Before starting 1.1, run `git diff HEAD --stat`, confirm the 10 modified + 1 untracked file correspond to Codex's described surface (pill presenter rewrite, AppStartupCoordinator, `preparationProgress` rename, staging-dir-only wipe, `.loading` phase), then commit. Without this gate, every subsequent step merges against an unstable baseline.

### 2. Missing: version string / build info in the menu-bar popover

For dogfood bug attribution, surface `CFBundleShortVersionString` + git SHA under the latest transcript. Zero new UI; one `Text()` in `MenuBarScene`. Add as a subtask of 1.13.

### 3. Missing: `addGlobalMonitorForEvents` nil-return logging

Plan mentions this in passing in 1.9 ("logs a warning if … returns nil") but does not prescribe where. Put it in `GlobalHotkeyMonitor.start()` with a stable signpost name so `log stream` can filter it.

### 4. BUG-07 clipboard-clobber deferral to Phase 3 is defensible but document the decision

Two weeks of Week-2 use produced no concrete report of clobber friction, and the fix ships with Settings (Phase 3). Punt is correct. Add a one-liner to Phase 1 "Non-goals" listing BUG-07 explicitly so dogfood knows to watch for clipboard-manager races.

### 5. Use existing `DevelopmentComposition`

`Tests/SeshatAppKitTests/DevelopmentComposition.swift` exists. Steps 1.4, 1.6, 1.12 can reuse its factories instead of inventing new ones. Call it out so executors don't duplicate.

### 6. Sibling-cross-plan semantic audit

User memory (`feedback_plan_reviews.md`) requires a "Forbidden Duplicates Semantic Audit" + "Sibling Cross-Plan Audit" in revisions. This plan supersedes `plans/PLAN_week3_phase1_stability_foundations.md` but no grep/diff confirms no forbidden-duplicate symbols survive. Add a pre-gate semantic grep, e.g. "no `prewarmTranscription()` reference exists anywhere post-Step 1.0 commit; no `downloadProgress` identifier survives in `MenuBarSceneModel`".

### 7. Phase 2.I asset-catalog mechanics need a pre-kickoff spike

The row reserves `.process("Resources")` on an executable target for bundling the logo asset. SPM supports this, but the `.icns` app icon is orthogonal — it requires `CFBundleIconFile` in Info.plist, which SPM does not inject for `.executableTarget`. Current `package-dev-app.sh` probably does. Assign an owner at Phase 1 gate to validate that `package-dev-app.sh` sets `CFBundleIconFile` when 2.G produces the `.icns`, or switch to runtime `NSApp.applicationIconImage = ...`.

### 8. Cross-cutting rule #8 enforcement mechanism is hand-wavy

Plan says "Configure in Package.swift or via `XCTestObservation`." `swift test` sequential execution is the default across targets but XCTest may still run test cases within one test class in parallel on Swift 6 concurrency runners. Pin the mechanism concretely: either use a static `NSLock` in `setUp()` around `testingBaseDirectoryOverride` mutation, or restructure tests to not share that global.

## Verified Claims (things I confirmed are correct)

1. **All five test targets exist** in `Package.swift` (lines 88-126): `SeshatCoreTests`, `SeshatAudioTests`, `SeshatTranscriptionTests`, `SeshatSessionTests`, `SeshatAppKitTests`. Adding `SessionCoordinatorActorTests.swift`, `ModelRegistryTests.swift`, `TranscriptStoreTests.swift` does NOT require new targets or Package.swift edits.

2. **`FluidAudioInferenceClient.swift` has zero `ParakeetArtifact` references** — confirmed via grep. Registry refactor does not need to touch it; plan's claim at line 146 is accurate.

3. **`SeshatCore/Config.swift` currently has no env-var or UserDefaults support** — confirmed. `resolvedBaseDirectory()` only branches on `testingBaseDirectoryOverride` + default path. Step 1.6's diff against spec is accurate modulo Critical #5.

4. **No hardcoded `SeshatBaseDirectoryPath` / `SESHAT_BASE_DIR` references exist anywhere in `Sources/`** — confirmed via grep. Step 1.6 introduces both without stomping existing call sites.

5. **No existing `UserDefaults` usage in `Sources/`** — confirmed. Step 1.6 is the first introduction; the domain-mismatch caveat in Critical #5 therefore has no precedent to follow.

6. **Phase boundary discipline is good.** Phase 1 contains no new design tokens, no logo work, no waveform, no `.icns`, no new windows. The only visual touches are informational banners (1.9, 1.10) and a text-only transcript preview (1.13). Phase 2 correctly owns all visual/design work. No Phase-2 scope leak detected.

7. **`~/Library/Application Support/Seshat/` default path is preserved** by the refactor (spec file 2's `resolvedBaseDirectory()` fallback). Backward-compat rule in `CLAUDE.md` honored.

8. **Cross-cutting rule #1 (TDD required) is honored for every step that introduces code**: 1.1 (mock transcriber test), 1.4 (presenter tests), 1.5 (registry tests), 1.6 (config tests), 1.9 (permission probing test), 1.11 (store tests), 1.12 (extended coordinator tests).

9. **BUG-07 punt to Phase 3 (3.H) is captured** at plan line 286: "BUG-07 clipboard clobber timing — configurable paste-restore delay default 0.5s". Correctly scoped.

10. **`Sources/SeshatAppKit/Overlay/PillOverlayPresenter.swift` already implements the correct mouse-event pathway** described in BUG-02/BACKLOG P0 #5, including drag threshold (4pt), `OverlayPanelInteractionState`, `canBecomeKey = true`, and `acceptsFirstMouse = true`. The remaining failure mode for clicks is therefore not on the pill side — it is likely menu-bar-click interception, matching Step 1.3's diagnosis framing.

11. **BACKLOG P0 #2 is already fixed** in `Sources/SeshatAppKit/Overlay/PillOverlayViewModel.swift:26-36` where `.recording` wins unconditionally and `.idle`/`.transcribing` can be overridden by `.downloading`. Plan needs to attribute this to Codex handoff (see Critical #10).

12. **BACKLOG P1 #3 is already fixed** in `Sources/SeshatTranscription/FluidAudioTranscriber.swift:220-251` where `ensureValidDownloadedModel` only calls `fileManager.removeItem(at: stagingDirectory)` on failure — the final `modelDirectory` is no longer wiped. Plan needs to attribute this to Codex handoff (see Critical #10).

13. **Phase 1 coverage of bundle UX audit P0/P1 items** (BUG-01 through BUG-10) is complete: BUG-01 (unresponsive start) → 1.1 + Suggestion #4 signposts; BUG-02 (pill clicks) → 1.3, 1.4; BUG-03, BUG-04, BUG-09 (permission banners + plain text menu + silent hotkey) → 1.9, 1.10 (plus Phase 2 for visual hierarchy); BUG-05 (record button state) → covered by existing `recordButton.isEnabled` in `MenuBarSceneModel`; BUG-06 (transcript overwrite) → 1.11-1.13 (history primitive) + Phase 3 SQLite; BUG-07 (clipboard) → Phase 3.H (punted, defensible); BUG-08 (onboarding) → Phase 3.C; BUG-10 (idle dot toggle) → Phase 2/3 settings. No orphaned P0/P1.
