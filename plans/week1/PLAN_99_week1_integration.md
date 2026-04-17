# Plan 99: Week 1 Integration

**Goal**: Wire `AppComposition` with the production types shipped by Plans 02, 03, and 04. Replace Plan 04's `DevelopmentComposition` fake wiring with the real `SessionCoordinator`. End-to-end verification: launch the menu bar app, tap record, dictate "hello world", see transcribed text appear in the popover with a copy button that works.
**Architecture**: thin composition-root file at `Sources/SeshatAppKit/Composition/AppComposition.swift` that constructs the single app-lifetime `SessionCoordinator` with production `AVAudioCaptureService` + `FluidAudioTranscriber`, and hands out the production `AppKitMicrophonePermissionRequester`. `SeshatApp.@main` consumes it instead of the test-only `DevelopmentComposition`.
**Tech Stack**: Swift 6, SwiftUI `MenuBarExtra`, AVFoundation, FluidAudio, URLSession, XCTest.
**Depends on**: Plans 00 (contract), 01 (SPM), 02 (`AVAudioCaptureService`), 03 (`FluidAudioTranscriber`), 04 (`AppKitMicrophonePermissionRequester` + `SeshatApp` shell). All five must be **complete and green** before Plan 99 starts.
**Plan 00 contract read**: Section C.6 (AppComposition API surface), D.6 (ownership rules — AppComposition owns the single coordinator; wiring is Plan 99's responsibility).

## Why this plan exists

Plan 00 Section C.6 defines the `AppComposition` surface but explicitly defers the implementation. Plans 01–04 each ship their layer (targets, capture, transcription, UI) but none of them can wire the composition root because that requires production types from two sibling plans. Plan 99 is the single integration step that converts four independently-built Swift modules into a running macOS app.

## A. Prerequisites (gate before starting)

Before the first commit of Plan 99, verify:

1. `git log --oneline` shows completion commits for Plans 00, 01, 02, 03, 04.
2. `swift build` succeeds for the whole workspace at the tip of Plan 04.
3. `swift test` succeeds for every test target except `SeshatAppKitTests/AppCompositionTests` (which does not exist yet — Plan 99 creates it).
4. Verify these concrete symbols exist and are `public` where required:
   - `SeshatAudio.AVAudioCaptureService` — conforms to `AudioCapturing`, `init()` takes no required args (or accepts `logger: SeshatLogger` with default).
   - `SeshatTranscription.FluidAudioTranscriber` — conforms to `Transcribing`, similar init shape.
   - `SeshatAppKit.AppKitMicrophonePermissionRequester` — conforms to `MicrophonePermissionRequesting`, public and `@MainActor` if needed.
   - `SeshatAppKit.SeshatApp` — injectable app shell from Plan 04 Option A. Must accept a `SessionCoordinator` and a `MicrophonePermissionRequesting` in its `init`.
5. Verify `Sources/SeshatAppKit/Composition/` directory exists (created as `.gitkeep` in Plan 01) but `AppComposition.swift` and `SeshatAppMain.swift` do NOT exist yet.
6. Verify `Tests/SeshatAppKitTests/DevelopmentComposition.swift` exists and is used only by Plan 04's tests (not by production `@main`).
7. Verify `grep -rn "@main" Sources/` returns **zero** matches — Plan 99 is about to ship the first `@main`. If a `@main` already exists, Plan 01 v2.1's placeholder fix was not applied (see Plan 01 v2.1 Step 3.7); stop and fix Plan 01 first.

Run:
```bash
swift build
swift test
ls Sources/SeshatAppKit/Composition/AppComposition.swift 2>&1 | grep -q "No such file" && echo "no AppComposition.swift yet: ok"
ls Sources/SeshatAppKit/Composition/SeshatAppMain.swift 2>&1 | grep -q "No such file" && echo "no SeshatAppMain.swift yet: ok"
test $(grep -rn "^@main" Sources/ 2>/dev/null | wc -l) -eq 0 && echo "no @main in Sources yet: ok"
```

If any check fails, the predecessor plan is not actually done. Fix upstream first; do NOT patch it inside Plan 99.

## B. Task breakdown

All commits use `git commit -m "plan-99 step N: <desc>"`. This plan has no Sapling; personal repo.

### Step 1. Add failing `AppCompositionTests`

- File: `Tests/SeshatAppKitTests/AppCompositionTests.swift`
- Write the failing test from Plan 00 Section E Step 10 (verbatim):

```swift
import XCTest
import SeshatCore
import SeshatSession
@testable import SeshatAppKit

@MainActor
final class AppCompositionTests: XCTestCase {
    func testMakeSessionCoordinatorReturnsSharedIdleActor() async {
        let first = AppComposition.makeSessionCoordinator()
        let second = AppComposition.makeSessionCoordinator()

        XCTAssertTrue(first === second)
        XCTAssertEqual(await first.state(), .idle)
    }

    func testMakeMicrophonePermissionRequesterReturnsProductionType() async {
        let requester = AppComposition.makeMicrophonePermissionRequester()
        XCTAssertTrue(requester is AppKitMicrophonePermissionRequester)
    }
}
```

- Run: `swift test --filter AppCompositionTests` → expected to fail (compile error: `AppComposition` undefined, `AppKitMicrophonePermissionRequester` not visible).
- Do NOT implement yet. Commit the failing test alone.
- Commit: `git commit -m "plan-99 step 1: add failing AppCompositionTests"`.

### Step 2. Create `AppComposition.swift`

- File: `Sources/SeshatAppKit/Composition/AppComposition.swift`
- Implementation:

```swift
import Foundation
import SeshatCore
import SeshatAudio
import SeshatTranscription
import SeshatSession

@MainActor
public enum AppComposition {
    public static let sessionCoordinator: SessionCoordinator = {
        let logger = SeshatLogger(category: SeshatLogCategory.session)
        let capture = AVAudioCaptureService(logger: SeshatLogger(category: SeshatLogCategory.audio))
        let transcriber = FluidAudioTranscriber(logger: SeshatLogger(category: SeshatLogCategory.transcription))
        return SessionCoordinator(capture: capture, transcriber: transcriber, logger: logger)
    }()

    public static func makeSessionCoordinator() -> SessionCoordinator {
        sessionCoordinator
    }

    public static func makeMicrophonePermissionRequester() -> any MicrophonePermissionRequesting {
        AppKitMicrophonePermissionRequester()
    }
}
```

Notes:
- The exact init signatures for `AVAudioCaptureService` and `FluidAudioTranscriber` are whatever Plans 02 and 03 shipped. If they take different default parameters (e.g. an injected `URLSession` or a logger), adjust the call sites here to match. This file is the ONLY place those production types are instantiated for production runs.
- `AppKitMicrophonePermissionRequester` lives in `Sources/SeshatAppKit/Permissions/` per Plan 04. It is visible to `AppComposition.swift` because they share the same `SeshatAppKit` target.

- Run: `swift test --filter AppCompositionTests/testMakeSessionCoordinatorReturnsSharedIdleActor` → expected to PASS.
- Run: `swift test --filter AppCompositionTests/testMakeMicrophonePermissionRequesterReturnsProductionType` → expected to PASS.
- Commit: `git commit -m "plan-99 step 2: wire production AppComposition"`.

### Step 3. Create the `@main` entry point that reads from `AppComposition`

**Context**: Plan 04 v2 ships `SeshatApp: App` as an **injectable** shell whose initializer takes `coordinator:` and `permissionRequester:` as required parameters. SwiftUI's synthesized `App.main()` expects a parameterless `init()`, so `SeshatApp` cannot itself be the `@main` entry point. Plan 99 creates a **separate** `@main` App conformer that lives alongside `AppComposition.swift` and wires production dependencies via stored-property initializers.

Three viable SwiftUI patterns exist:

| Option | Shape | Chosen? | Rejected because |
|---|---|---|---|
| A: `SeshatApp` gains a parameterless `init()` that reads from `AppComposition` | Breaks Plan 04's injection contract; creates a circular knowledge edge (Plan 04 references AppComposition which is Plan 99-owned) | ✗ | bleeds Plan 99 concerns into Plan 04 |
| B: Top-level `nonisolated(unsafe)` vars carry dependencies; `SeshatApp.init()` reads them | Works but uses global mutable state | ✗ | ugly and easy to misuse |
| C: Plan 99 creates a **separate** `@main App` conformer (`SeshatAppMain`) that owns a stored `MenuBarSceneModel` built from `AppComposition`; its body delegates to the same view as `SeshatApp.body` | Plan 04 stays purely injectable and test-only; Plan 99 owns all production wiring | ✓ | (chosen) |

**File**: `Sources/SeshatAppKit/Composition/SeshatAppMain.swift` (NEW, lives in `Composition/` alongside `AppComposition.swift`)

**Red**: `AppEntryPointTests/testSeshatAppMainBuildsSceneModelFromComposition`
```swift
import XCTest
import SeshatCore
import SeshatSession
@testable import SeshatAppKit

@MainActor
final class AppEntryPointTests: XCTestCase {
    func testSeshatAppMainBuildsSceneModelFromComposition() async {
        let entry = SeshatAppMain()
        // Production wiring reads the same shared coordinator
        XCTAssertTrue(entry.coordinator === AppComposition.sessionCoordinator)
        XCTAssertEqual(await entry.coordinator.state(), .idle)
    }
}
```

**Green**: implement `SeshatAppMain`:

- DELETE `Sources/SeshatAppKit/main.swift` (the Plan 01 v2.2 placeholder). Verify deletion: `test ! -f Sources/SeshatAppKit/main.swift`.

```swift
import SwiftUI
import SeshatCore
import SeshatSession

@main
struct SeshatAppMain: App {
    let coordinator: SessionCoordinator
    let permissionRequester: any MicrophonePermissionRequesting

    @StateObject private var sceneModel: MenuBarSceneModel

    init() {
        let coordinator = AppComposition.sessionCoordinator
        let permissionRequester = AppComposition.makeMicrophonePermissionRequester()
        self.coordinator = coordinator
        self.permissionRequester = permissionRequester
        _sceneModel = StateObject(wrappedValue: MenuBarSceneModel(
            coordinator: coordinator,
            permissionRequester: permissionRequester,
            permissionStateProvider: { .notYetRequested }
        ))
    }

    var body: some Scene {
        MenuBarScene(model: sceneModel)  // reuses the same Scene type Plan 04 defined
    }
}
```

Notes:
- `SeshatAppMain` is NEW — Plan 04's `SeshatApp` remains the injectable test shell and continues to be useful for the development-time tests.
- Both types' bodies produce the same `MenuBarScene(model:)` — the Scene is defined once in Plan 04 and reused.
- The `@main` attribute lives only here. `grep -r "@main" Sources/` must show exactly one match after Plan 99.

- Run: `swift test --filter AppEntryPointTests/testSeshatAppMainBuildsSceneModelFromComposition` → PASS.
- Commit: `git commit -m "plan-99 step 3: add @main entry point wired to AppComposition"`.

### Step 3b. Verify single-`@main` invariant

- Add a verification step (not a unit test, just a shell check):

```bash
grep -rn "^@main" Sources/ | tee /tmp/main-locations.txt
# Expected: exactly one line, in Sources/SeshatAppKit/Composition/SeshatAppMain.swift
test $(wc -l < /tmp/main-locations.txt) -eq 1
```

If the check fails, stop and audit. Common cause: a lingering `@main` scaffold from Plan 01 v1 that wasn't replaced by the v2.1 placeholder fix.

- Commit: `git commit -m "plan-99 step 3b: verify single @main invariant"`.

- Run: `swift test --filter AppEntryPointTests` → PASS.
- Commit: `git commit -m "plan-99 step 3: wire @main to AppComposition"`.

### Step 4. Full workspace build + test sweep

- Run `swift build` — must succeed with zero warnings that mention `nonisolated(unsafe)` except for `SeshatConfig.testingBaseDirectoryOverride` (the one approved case).
- Run `swift test` — every test target passes.
- Run `swift test --parallel` — ensure no test ordering dependencies.
- Commit nothing; this is a verification gate.

### Step 5. Manual end-to-end verification runbook

- File: `Tests/SeshatAppKitTests/ManualWeek1Verification.md`
- Contents: a runbook for a human tester to execute once. Do NOT try to automate this; it requires a real microphone, real model download, real display.

Runbook:

```markdown
# Manual Week 1 End-to-End Verification

Run this on a macOS 14+ Apple Silicon Mac after Plan 99 Step 4 passes.

1. `swift run SeshatAppKit` — menu bar icon appears (SF Symbol "mic") in the status bar.
2. First-launch permission flow:
   - Click the menu bar icon → popover opens.
   - Click "Grant microphone access" → macOS system dialog appears.
   - Click Allow.
   - Popover state updates to "idle, ready to record".
3. First-run model download:
   - Watch the popover for model-download progress (indeterminate or percent).
   - Verify `~/Library/Application Support/Seshat/models/parakeet-tdt-0.6b-v2/` populates with:
     - `Preprocessor.mlmodelc`
     - `Encoder.mlmodelc`
     - `Decoder.mlmodelc`
     - `JointDecision.mlmodelc`
     - `parakeet_vocab.json`
   - Progress finishes → UI shows "idle, ready to record".
4. Record a short utterance:
   - Click Record → icon flips to red "mic.fill"; state label shows "recording".
   - Say "hello world" clearly.
   - Click Stop → state label shows "transcribing" briefly, then "idle".
5. Verify transcript:
   - Popover shows the transcribed text ("hello world" or a close variant).
   - Click Copy → open any app (TextEdit) and paste → the transcript lands.
6. Quit the app. Relaunch.
   - Model is NOT re-downloaded (second-launch fast path works).
   - Permission is NOT re-prompted.

## Acceptance

Week 1 is complete when steps 1–6 all pass without manual intervention beyond the clicks specified. File any deviation as a follow-up issue, not a Week 1 blocker, unless the deviation prevents reaching step 5.

## Known Week 1 gaps (expected — NOT verification failures)

- No global hotkey. Must click the menu bar.
- No paste injection. Must click Copy then Cmd-V.
- No filler/punctuation cleanup. Raw Parakeet output.
- No notes database. Transcript is visible only in the popover until replaced.
- Clipboard clobbers whatever was on the pasteboard before Copy. (Week 2 adds save/restore.)
```

- Commit: `git commit -m "plan-99 step 5: add Week 1 manual verification runbook"`.

### Step 6. Tag Week 1 complete

- Tag the final commit:
```bash
git tag -a week-1-complete -m "Week 1: working dictation (record → transcribe → copy)."
```
- Update `README.md`'s "Status" line to "Week 1 complete — daily dictation usable via menu bar."
- Commit: `git commit -m "plan-99 step 6: tag week-1-complete"`.

## C. Dependency table

| Group | Steps | Can Parallelize | Notes |
|---|---|---|---|
| 1 | 1 | — | Add failing test first (TDD). |
| 2 | 2 | No | Implement `AppComposition`; test goes green. |
| 3 | 3 | No | Add `SeshatAppMain` with the only `@main`; smoke test goes green. |
| 3b | 3b | No | Verify single-`@main` invariant across `Sources/`. |
| 4 | 4 | No | Full workspace sweep. |
| 5 | 5 | No | Manual runbook (document-only). |
| 6 | 6 | No | Tag + README update. |

No parallelism — Plan 99 is a serial finalization. Total estimated human time: 30–60 minutes of coding/verification, plus however long the real Parakeet download takes on first run.

## D. Handoff signals (Week 1 → Week 2)

After Plan 99:

- `AppComposition.sessionCoordinator` is the single production coordinator for the app's lifetime.
- `SeshatAppMain` (a new App conformer in `Sources/SeshatAppKit/Composition/`) is the one-and-only `@main`; it constructs a `MenuBarSceneModel` from `AppComposition` and reuses Plan 04's `MenuBarScene`.
- `SeshatApp` (Plan 04's injectable shell) remains in `Sources/SeshatAppKit/` and is used by Plan 04's tests and `DevelopmentComposition`; production never instantiates it.
- `grep -rn "^@main" Sources/` returns exactly one line (pointing at `SeshatAppMain.swift`).
- Manual runbook end-to-end passes on a dev machine.
- Week 2 work (global hotkey, paste injection, post-processing filler/punctuation, floating pill overlay) starts from a working dictation pipeline.
- `DevelopmentComposition.swift` remains in `Tests/SeshatAppKitTests/` for future test-only use; it is NOT touched by production code after Plan 99.

## E. Explicit non-goals for Plan 99

- NO production post-processing pipeline. (Week 2)
- NO global hotkey. (Week 2)
- NO clipboard save/restore. (Week 2)
- NO notes persistence. (Week 3)
- NO settings UI. (Phase 2)
- NO distribution / notarization / Homebrew formula. (Phase 4)

## F. Open Questions (carry-over from upstream plans)

1. Whether `AVAudioCaptureService.init()` signature exactly matches the call in Step 2 depends on Plan 02's final shipped shape. If Plan 02 adds required arguments, adjust Step 2's wiring accordingly.
2. Same for `FluidAudioTranscriber.init()` — Plan 03 pinned `exact: "0.13.6"` but its Swift init signature is defined in Plan 03 itself; verify before Step 2.
3. First-run model download UX (indeterminate spinner vs. percent vs. log-only) is Plan 04's call; Plan 99 wires it but does not design it.
4. If the manual runbook's step 4 transcript quality is noticeably worse than a typical dictation tool, that's a Week 2 backlog item (post-processing), NOT a Week 1 failure.

---

**Execution order reminder**: Plans 00 + 01 + 02 + 03 + 04 → Plan 99. Do not start Plan 99 until every upstream `swift test` is green.
