# #033 / #056 runtime-bug review

## 1. H1 verdict
**FAIL as written.** The re-entry diagnosis is right, but the proposed "mirror `startHoldRecording()` eager publish" is not a drop-in. `toggleCapture()` starts from `.idle` only ([Sources/PersonalScribeSession/Pipeline/Orchestrator/SessionPipelineOrchestrator.swift:218-223]). `startRecording()` freezes `activeSessionRecipe`, then awaits `capture.start()` before publishing `.capturing` ([Sources/PersonalScribeSession/Pipeline/Orchestrator/SessionPipelineOrchestrator.swift:399-403], [Sources/PersonalScribeSession/Pipeline/Orchestrator/SessionPipelineOrchestrator.swift:427-436]), so a second caller can still observe `.idle`. `AVAudioCaptureService.start()` rejects that second live start once `isCapturing` is true ([Sources/PersonalScribeAudio/AVAudioCaptureService.swift:58-61], [Sources/PersonalScribeAudio/AVAudioCaptureService.swift:135-136]). That matches error 1.

I would not literally mirror the hold path, because `startRecording()` already has a deliberate "prepare before publish" invariant ([Sources/PersonalScribeSession/Pipeline/Orchestrator/SessionPipelineOrchestrator.swift:416-425]) and a regression test pinning that startup contract ([Tests/PersonalScribeSessionTests/Pipeline/SessionPipelineOrchestratorTests.swift:294-335]). Safer fix: add a private start-in-flight guard at the top of `startRecording()` before [Sources/PersonalScribeSession/Pipeline/Orchestrator/SessionPipelineOrchestrator.swift:394].

```swift
private var startRecordingInFlight = false

private func startRecording() async {
    guard !startRecordingInFlight else {
        logger.info("Ignored duplicate start while capture.start() is still in flight")
        return
    }
    startRecordingInFlight = true
    defer { startRecordingInFlight = false }
    // existing body...
}
```

## 2. H2 verdict
**PASS.** Both contenders write `activeSessionRecipe` at [Sources/PersonalScribeSession/Pipeline/Orchestrator/SessionPipelineOrchestrator.swift:400]. The losing start clears it at [Sources/PersonalScribeSession/Pipeline/Orchestrator/SessionPipelineOrchestrator.swift:442]. The winning start can still keep recording, but stop later reaches `runBoundProcessing()` via [Sources/PersonalScribeSession/Pipeline/Orchestrator/SessionPipelineOrchestrator.swift:545-551] and [Sources/PersonalScribeSession/Pipeline/Orchestrator/SessionPipelineOrchestrator.swift:617-621], and that method throws `invalidState` when `activeSessionRecipe` is nil ([Sources/PersonalScribeSession/Pipeline/Orchestrator/SessionPipelineOrchestrator.swift:718-724]). That matches error 2.

I would fix the root cause, not just guard the damage: remove the catch-time clear in `startRecording()` and the analogous hold-start catch at [Sources/PersonalScribeSession/Pipeline/Orchestrator/SessionPipelineOrchestrator.swift:528]. The true-discard cancel path is the intentional clear ([Sources/PersonalScribeSession/Pipeline/Orchestrator/SessionPipelineOrchestrator.swift:451-466]).

```swift
} catch {
    handleStageFailure(
        makeStageFailure(stage: .capture, error: error, fallback: .audioEngineFailure)
    )
}
```

## 3. What triggered the duplicate `startRecording`
I did **not** find a hotkey-stack duplication bug. `AppComposition` owns one shared `hotkeyMonitor` ([Sources/PersonalScribeAppKit/Composition/AppComposition.swift:268-280]) and starts it once at startup ([Sources/PersonalScribeAppKit/Composition/AppComposition.swift:403-410]). `GlobalHotkeyMonitor.start()` is idempotent ([Sources/PersonalScribeAppKit/Hotkeys/GlobalHotkeyMonitor.swift:146-149]) and registers exactly one local and one global decider ([Sources/PersonalScribeAppKit/Hotkeys/GlobalHotkeyMonitor.swift:168-175]). `KeyEventRouter` keeps those channels separate ([Sources/PersonalScribeAppKit/Hotkeys/KeyEventRouter.swift:66-68], [Sources/PersonalScribeAppKit/Hotkeys/KeyEventRouter.swift:131-147]), and matching hotkeys are swallowed in the CG tap before app delivery ([Sources/PersonalScribeAppKit/Hotkeys/HotkeyEventTap.swift:21-22], [Sources/PersonalScribeAppKit/Hotkeys/HotkeyEventTap.swift:116-118], [Sources/PersonalScribeAppKit/Hotkeys/GlobalHotkeyMonitor.swift:260-281]).

The proven trigger is narrower: any two independent callers reaching `toggle()/toggleCapture()` before `.capturing` publishes can reproduce the race ([Sources/PersonalScribeAppKit/Composition/AppComposition.swift:247-251], [Sources/PersonalScribeAppKit/Composition/PersonalScribeAppMain.swift:111-113], [Sources/PersonalScribeAppKit/MenuBar/MenuBarSceneModel.swift:116-123], [Sources/PersonalScribeSession/Pipeline/Orchestrator/SessionPipelineOrchestrator.swift:427-436]). From this audit alone, I cannot prove which caller supplied the second start.

## 4. EOU inconsistency root cause(s)
Most likely cause: **EOU-only delivery plus stop-before-EOU timing**, not paste throttling. `consumeLiveStreamingEvent()` sends live cursor output only for `.endOfUtterance`, never `.partial` ([Sources/PersonalScribeSession/Pipeline/Orchestrator/SessionPipelineOrchestrator.swift:1317-1335]). `LiveCursorOutput.deliverFinal()` is a no-op ([Sources/PersonalScribeAppKit/Output/LiveCursorOutput.swift:99-105]), so stop-time finalize does not backfill a missed live paste. The adapter emits `.endOfUtterance` only from FluidAudio's EOU callback ([Sources/PersonalScribeTranscription/Adapters/FluidAudioStreamingTranscriberAdapter.swift:167-172]) and emits `.finalized` only after stream end via `manager.finish()` ([Sources/PersonalScribeTranscription/Adapters/FluidAudioStreamingTranscriberAdapter.swift:200-220]). That matches "only when I didn't speak for a bit."

I do not see strong code evidence that an 80 ms paste throttle is the primary fix. App-side deliveries are serialized (`LiveCursorOutput` is `@MainActor` at [Sources/PersonalScribeAppKit/Output/LiveCursorOutput.swift:39-40], and the orchestrator awaits each call at [Sources/PersonalScribeSession/Pipeline/Orchestrator/SessionPipelineOrchestrator.swift:1331-1333]). Secondary silent-drop contributors exist, but they do not explain the pause-sensitive pattern.

## 5. Anything Claude missed
`LiveCursorOutput.deliverPartial()` ignores `pasteShortcutPoster()`'s `Bool` ([Sources/PersonalScribeAppKit/Output/LiveCursorOutput.swift:96]) even though `postPasteShortcut()` can fail and return `false` when it cannot create events ([Sources/PersonalScribeAppKit/Output/LiveCursorOutput.swift:162-175]). That is an additional silent live-paint loss path: clipboard write succeeds, no paste happens, and the sink does not log or retry.
