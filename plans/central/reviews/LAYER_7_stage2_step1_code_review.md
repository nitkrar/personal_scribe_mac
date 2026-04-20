# Layer 7 Stage 2 Step 1 Code Review

## Verdict
REQUEST CHANGES

The public surface is mostly migrated cleanly: both `SessionCoordinator` initializers are still present with the same signatures, `toggle()` / `prepareTranscriber()` now route through `SessionPipelineOrchestrator`, the new `CoordinatorPipelineTranscriber` preserves the Layer 6 per-recording transcriber pinning, and the 14 legacy inline-lifecycle helpers are deletion-ready dead code. The remaining issue is a behavioral regression on `audioLevelStream()`: the coordinator now relays pipeline levels through an un-awaited background observer task, so the delegated path is no longer equivalent to the old direct capture fan-out.

## Findings by severity

### Blocker
None.

### Major
1. `SessionCoordinator.audioLevelStream()` no longer preserves the old "every level during recording" contract because it now depends on an asynchronously started relay task instead of subscribing on the recording path itself. The new bridge is:

   ```swift
   Task { [weak owner, pipeline] in
       let stream = await pipeline.audioLevelStream()
       for await level in stream {
           guard let owner else {
               return
           }
           await owner.publishAudioLevel(level)
       }
   }
   ```

   at `Sources/SeshatSession/SessionCoordinator.swift:230-237`. The public coordinator stream still serves values from its own cached broadcaster at `Sources/SeshatSession/SessionCoordinator.swift:129-147` and `Sources/SeshatSession/SessionCoordinator.swift:255-260`, while the upstream pipeline stream itself yields an immediate cached sample on subscription at `Sources/SeshatSession/Pipeline/Orchestrator/SessionPipelineOrchestrator.swift:114-125`. That extra hop makes early level delivery scheduler-dependent and can replay the pipeline's initial `0.0` into coordinator subscribers after they already consumed the coordinator's own initial `0.0`. The two known reds in `Tests/SeshatSessionTests/SessionCoordinatorAudioLevelTests.swift:12-56` and `Tests/SeshatSessionTests/SessionCoordinatorAudioLevelTests.swift:77-126` match this code path, so this reads as a real coordinator-surface regression, not just stale expectations.

### Minor
None.

### Nit
None.

### Question
None.

## Dead-method audit

| Method name | Reachable? | Evidence |
| --- | --- | --- |
| `startRecording()` | No | `toggle()` now calls `pipeline.toggleCapture()` instead of the legacy branch at `Sources/SeshatSession/SessionCoordinator.swift:99-103`; the dead definition is `Sources/SeshatSession/SessionCoordinator.swift:270-298`. |
| `stopRecordingAndTranscribe()` | No | Same entry-point cutover: no public caller remains after `Sources/SeshatSession/SessionCoordinator.swift:99-103`; dead definition is `Sources/SeshatSession/SessionCoordinator.swift:300-355`. |
| `persistTranscript(text:audioDuration:processingDuration:)` | No | Only referenced from dead `stopRecordingAndTranscribe()` at `Sources/SeshatSession/SessionCoordinator.swift:346-350`; definition is `Sources/SeshatSession/SessionCoordinator.swift:357-379`. |
| `consumeCaptureStream(_:)` | No | Only referenced from dead `startRecording()` at `Sources/SeshatSession/SessionCoordinator.swift:292-294`; definition is `Sources/SeshatSession/SessionCoordinator.swift:387-395`. |
| `makeReplayStream(from:)` | No | Only referenced from dead `stopRecordingAndTranscribe()` at `Sources/SeshatSession/SessionCoordinator.swift:338`; definition is `Sources/SeshatSession/SessionCoordinator.swift:397-404`. |
| `map(_:default:)` | No | Only referenced from dead legacy helpers at `Sources/SeshatSession/SessionCoordinator.swift:296`, `Sources/SeshatSession/SessionCoordinator.swift:353`, and `Sources/SeshatSession/SessionCoordinator.swift:393`; definition is `Sources/SeshatSession/SessionCoordinator.swift:406-413`. |
| `prepareTranscriberInBackground(using:)` | No | Only referenced from dead `startRecording()` at `Sources/SeshatSession/SessionCoordinator.swift:291`; definition is `Sources/SeshatSession/SessionCoordinator.swift:415-427`. |
| `resolvedTranscriberForPreparation()` | No | Public `prepareTranscriber()` now delegates to `pipeline.prepareTranscriber()` at `Sources/SeshatSession/SessionCoordinator.swift:154-160`; the legacy helper definition is `Sources/SeshatSession/SessionCoordinator.swift:429-436` and has no live caller on `SessionCoordinator`. |
| `resolveRecordingSessionTranscriber()` | No | Only referenced from dead `startRecording()` at `Sources/SeshatSession/SessionCoordinator.swift:275`; the live adapter call at `Sources/SeshatSession/SessionCoordinator.swift:567-568` targets `CoordinatorPipelineTranscriber.resolveRecordingSessionTranscriber()`, a different method on a different type. |
| `transcriberForStopPath()` | No | Only referenced from dead `stopRecordingAndTranscribe()` at `Sources/SeshatSession/SessionCoordinator.swift:321`; the live adapter calls at `Sources/SeshatSession/SessionCoordinator.swift:581-582` and `Sources/SeshatSession/SessionCoordinator.swift:589-590` target the adapter actor's helper instead. |
| `resolvedActiveTranscriber()` | No | Only referenced from dead helpers at `Sources/SeshatSession/SessionCoordinator.swift:435` and `Sources/SeshatSession/SessionCoordinator.swift:457`; same-name live helper is the adapter method at `Sources/SeshatSession/SessionCoordinator.swift:627-637`. |
| `activeVoiceModel()` | No | Only referenced from dead helpers at `Sources/SeshatSession/SessionCoordinator.swift:445` and `Sources/SeshatSession/SessionCoordinator.swift:466`; same-name live helper is the adapter method at `Sources/SeshatSession/SessionCoordinator.swift:639-647`. |
| `resolvedModelBoundTranscriber(for:)` | No | Only referenced from dead helpers at `Sources/SeshatSession/SessionCoordinator.swift:446` and `Sources/SeshatSession/SessionCoordinator.swift:467`; same-name live helper is the adapter method at `Sources/SeshatSession/SessionCoordinator.swift:649-657`. |
| `observeDownloadProgress(for:)` | No | Only referenced from dead legacy helpers at `Sources/SeshatSession/SessionCoordinator.swift:431`, `Sources/SeshatSession/SessionCoordinator.swift:441`, `Sources/SeshatSession/SessionCoordinator.swift:448`, `Sources/SeshatSession/SessionCoordinator.swift:462`, and `Sources/SeshatSession/SessionCoordinator.swift:468`; the live progress path is now the separate observer task at `Sources/SeshatSession/SessionCoordinator.swift:240-245`, plus the adapter actor's own helper at `Sources/SeshatSession/SessionCoordinator.swift:659-671`. |

## Test-regression analysis

`SessionCoordinatorAudioLevelTests.testAudioLevelStreamRepublishesLevelsDuringRecording` is a production regression in the delegated coordinator path. The coordinator no longer forwards levels by subscribing directly inside `startRecording()`; it now waits for the detached observer in `Sources/SeshatSession/SessionCoordinator.swift:230-237` to attach to `pipeline.audioLevelStream()`. That upstream stream emits an initial cached value immediately (`Sources/SeshatSession/Pipeline/Orchestrator/SessionPipelineOrchestrator.swift:114-125`), and the fake capture emits canned levels as soon as the first subscriber asks for the level stream (`Sources/SeshatTestSupport/FakeAudioCapturing.swift:88-105`). Together, that makes the first few relayed values race-prone and explains why this test can now see either an extra `0.0` or miss early canned samples.

`SessionCoordinatorAudioLevelTests.testMultipleSubscribersEachReceiveEveryLevel` has the same root cause and should be classified the same way: production regression, not test-stale. Both subscribers attach to the coordinator's rebroadcast stream, so any duplicate/drop introduced at the coordinator relay layer is shared fan-out state. The direct orchestrator surface still implements this contract synchronously inside the pipeline actor (`Sources/SeshatSession/Pipeline/Orchestrator/SessionPipelineOrchestrator.swift:152-157`, `Sources/SeshatSession/Pipeline/Orchestrator/SessionPipelineOrchestrator.swift:170-176`); the regression is specifically the extra SessionCoordinator relay added in this step.

`SessionCoordinatorModelSelectionTests.testRecordingSessionStaysPinnedWhileNextRecordingUsesUpdatedActiveModel` does not read as a true pinning regression from the code I reviewed. `CoordinatorPipelineCapture.start()` calls `beginRecordingSession()` before returning the capture stream (`Sources/SeshatSession/SessionCoordinator.swift:520-523`), `CoordinatorPipelineTranscriber.beginRecordingSession()` snapshots the active transcriber into `recordingSessionTranscriber` (`Sources/SeshatSession/SessionCoordinator.swift:566-569`, `Sources/SeshatSession/SessionCoordinator.swift:605-617`), `prepare()` prefers that pinned instance (`Sources/SeshatSession/SessionCoordinator.swift:571-573`, `Sources/SeshatSession/SessionCoordinator.swift:596-603`), and the stop path transcribes through the same pinned instance before clearing it (`Sources/SeshatSession/SessionCoordinator.swift:588-594`, `Sources/SeshatSession/SessionCoordinator.swift:619-625`). Hypothesis: if this test is red on trunk, the red is stale/misattributed or is failing on some other coordinator-side relay behavior, not on the Layer 6 pinning guarantee itself.

## Summary

`5b3d9a2` plus fix-forward `c7689f5` gets the API-shape migration mostly right: public initializer signatures are preserved, the snapshot-to-`SessionState` / `lastResult` mapping is coherent, the Layer 6 recording-session transcriber pinning survives inside `CoordinatorPipelineTranscriber`, the 14 legacy inline helpers are genuinely unreachable, and `c7689f5` fixes the obvious Swift 6 `nonisolated` conformance hole for `modelDownloadProgress()`. I did not find a second isolation bug in the new adapter. The remaining review-blocking issue is the coordinator-level audio relay regression introduced by `startPipelineObservers`.
