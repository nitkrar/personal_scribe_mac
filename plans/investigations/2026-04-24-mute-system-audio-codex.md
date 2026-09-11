# Verdict
ship-with-changes

# Must-fix
- `SystemOutputMuter` cannot latch only `priorState: Bool?`. It must also remember exactly which device(s) it muted. Otherwise a mid-recording route change makes `restore()` apply the old mute state to the new default output and can leave the original device muted.
- The capture-stream error path does not guarantee wrapper cleanup. `consumeCaptureStream()` goes straight to `handleStageFailure(...)` when the stream throws (`Sources/PersonalScribeSession/Pipeline/Orchestrator/SessionPipelineOrchestrator.swift:614-660`), while only normal stop/cancel paths call `capture.stop()` (`:332-339`, `:416-422`). A wrapper that restores only in `stop()` will leak mute on "start succeeded, later stream threw."
- Clean quit is not covered today. The menu-bar quit path calls `NSApplication.shared.terminate(nil)` directly (`Sources/PersonalScribeAppKit/MenuBar/StatusItemController.swift:149-150`), and I could not find a termination hook that routes through `coordinator.stopIfActive()`. That is a real "leave the Mac muted" path.
- `kAudioHardwarePropertyDefaultOutputDevice` alone is not the whole story if the promise is "system audio." HAL separates `kAudioHardwarePropertyDefaultOutputDevice` from `kAudioHardwarePropertyDefaultSystemOutputDevice` for alerts/notifications. Either mute/restore both, or narrow the user-facing copy.

# Should-fix
- Make the CoreAudio seam fallible. `kAudioDevicePropertyMute` is not guaranteed to exist or be settable on every route, so `isMuted() -> Bool` / `setMuted(_:)->Void` forces the implementation to guess or silently ignore `OSStatus`. Probe `AudioObjectHasProperty` / `AudioObjectIsPropertySettable` and degrade explicitly.
- `MutingAudioCapture` belongs in `PersonalScribeAudio`, not `PersonalScribeSession`. It is an audio-side decorator; Session already has its own coordinator-specific wrapper and does not need to learn about output-device policy.
- Add one integration test above the wrapper for "capture stream throws after successful start restores mute." The proposed 8 tests mostly cover the new types in isolation and miss the real leak. Also, the brief is stale about preference tests: comparable prefs already have direct tests in `Tests/PersonalScribeAppKitTests/Settings/AutoPasteEnabledPreferenceTests.swift:4-45` and `Tests/PersonalScribeAppKitTests/Settings/ClipboardRestoreEnabledPreferenceTests.swift:4-46`.

# Nits
- The "already muted" test is not fluff. It covers the restore-to-`true` branch and matches the manual case "already-muted stays muted after recording."
- Keeping the muter as an actor is fine even though CoreAudio property calls are synchronous; the value is serializing the latch state, not making HAL async.
- Reading the pref at `start()` and always restoring at `stop()` is the right mid-session-toggle behavior. Turning the setting off while recording should not strand the machine muted.
- I could not verify from the brief alone whether HAL mute writes trigger any extra entitlement/TCC requirement. My expectation for an ad-hoc, unsandboxed app is "no new prompt," but I would treat that as manual verification, not paper certainty.

# Alternatives considered
- I do not see a materially simpler supported macOS API than HAL property writes. The simplification worth taking is contractual, not technical: if you want to stay small, scope the feature to "mute the output device active when recording starts" and accept route changes / crash recovery as best-effort rather than claiming full system-wide mute semantics.
