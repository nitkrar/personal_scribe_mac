# Verdict
ship-with-changes

# What I would keep from the simpler pass
- Keep the mute latch inside `AVAudioCaptureService`. That is the right simplification. The service already owns `start()`, `stop()`, `finishWithError()`, and `handleContinuationTermination()`, so restore logic belongs with those teardown points.
- Keep quit handling cheap: route the menu-bar `.quit` action through `coordinator.stopIfActive()` before `NSApplication.shared.terminate(nil)`.
- Keep the test surface narrow. This feature does not need a wide new session-layer abstraction just to be "clean."

# What I would change
- I would not make AppleScript / `NSAppleScript` the default implementation.
- My preferred v1 is still small, but native: add a tiny `SystemOutputMuter` in `PersonalScribeAudio` and inject it into `AVAudioCaptureService`.
- Scope it narrowly:
  - mute only the default output device present at `start()`
  - store `(deviceID, priorMuted)`
  - on restore, only write back to that same device if it still exists; otherwise log and skip
- This matches the implementation style we observed in Wispr Flow, avoids the old scripting runtime, and lets us handle `OSStatus` / "mute not supported" cases explicitly.
- If the UI copy literally says "system audio", either tighten the wording to "mute output while recording" or treat alert / notification routing as a later extension.

# Minimal implementation I would ship
1. Add `MuteOutputWhileRecordingPreference` and one toggle in `GeneralTab`.
2. Add `SystemOutputMuter` in `PersonalScribeAudio`.
3. Inject `shouldMuteOutput` plus the muter into `AVAudioCaptureService`.
4. In `start()`, if the preference is on, call `muteIfNeeded()` before engine start; if startup fails, restore immediately.
5. In `stop()`, `finishWithError()`, and `handleContinuationTermination()`, call `restoreIfNeeded()` after engine teardown.
6. Change the menu-bar `.quit` action to stop the active session before terminate.

# Why this is the right simplification
- No session-layer wrapper
- No helper app
- No interruption monitor
- No "mute only if media is playing" gate
- No promise to track mid-recording route changes perfectly

# If you insist on the AppleScript variant
- I would treat it as a v0 spike, not the default landed design.
- Do not swallow script failures; log them.
- Verify it on hardware before trusting it: start / stop, already-muted, quit while recording, and route change.

# Tests and verification
- `testCaptureStopRestoresOutputWhenStartingUnmuted`
- `testCaptureStopPreservesAlreadyMutedState`
- `testCaptureRuntimeFailureStillRestoresMute`
- Add a manual checklist entry for real-machine verification. Passing tests here only prove control-flow wiring, not that macOS mute semantics match the intended user-visible behavior.
