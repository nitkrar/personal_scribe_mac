# Recommended approach
For this app, muting system audio is a small feature: use AppleScript Standard Additions (`get volume settings` / `set volume output muted`) and keep the mute latch inside `AVAudioCaptureService`, not in a new CoreAudio subsystem. I do not see a public macOS API simpler than that, and a read plus a no-op write via `osascript` both executed cleanly on this machine. I would not add a session-layer decorator unless you want stricter modularity later; the capture service already owns normal stop, start failure, and runtime-failure teardown.

# Minimal code sketch
```swift
import Foundation

struct SystemAudioMuter {
    private var priorMuted: Bool?

    mutating func muteIfNeeded() {
        guard priorMuted == nil else { return }
        priorMuted = run("output muted of (get volume settings)")?.booleanValue ?? false
        _ = run("set volume output muted true")
    }

    mutating func restoreIfNeeded() {
        guard let priorMuted else { return }
        _ = run("set volume output muted \(priorMuted)")
        self.priorMuted = nil
    }

    private func run(_ source: String) -> NSAppleEventDescriptor? {
        NSAppleScript(source: source)?.executeAndReturnError(nil)
    }
}
```

# Minimal plumbing
- Add `MuteOutputWhileRecordingPreference` beside the existing boolean settings prefs and one toggle in `GeneralTab`.
- Give `AVAudioCaptureService` a `SystemAudioMuter` field plus `shouldMuteOutput: @Sendable () -> Bool`.
- In `start()`, if the pref is on, call `muter.muteIfNeeded()` before engine start; if startup throws, immediately `restoreIfNeeded()`.
- In `stop()`, `finishWithError()`, and `handleContinuationTermination()`, call `restoreIfNeeded()` after engine teardown.
- Change the menu-bar `.quit` action to stop an active recording before `NSApplication.shared.terminate(nil)`.

# Minimal tests
- `testCaptureStopRestoresOutputWhenStartingUnmuted` — would fail if the normal record/stop path leaves the machine muted.
- `testCaptureStopPreservesAlreadyMutedState` — would fail if recording wrongly unmutes a machine the user had muted before starting.
- `testCaptureRuntimeFailureStillRestoresMute` — would fail if a stream error leaks mute because `stop()` was never called.

# Quit-path handling
`route-through-stop` — this app already has a single explicit menu-bar quit action, and stopping there is the cheapest way to cover clean quit without inventing a global termination subsystem.

# Risks I cannot verify
- I do not expect Automation TCC here because this uses Standard Additions directly, not `tell application "..."`, but I did not verify a fresh-install prompt story end-to-end.
- I verified read and no-op write via `osascript`; I did not run a real mute/unmute cycle from this session.
- I cannot paper-prove whether `output muted` follows every mid-recording route change exactly like the keyboard mute key; for this version I would accept "behaves like system mute in normal use" rather than device-identity guarantees.
- If the app later becomes sandboxed or its signing model changes, re-check this approach before carrying it forward.
- `NSAppleScript` is old API; if it proves finicky off-main, move only the script execution to `MainActor` rather than escalating to CoreAudio.

# Why this is simpler than the prior pass
- No CoreAudio HAL property code.
- No default-output vs system-output split.
- No device-identity tracking across route changes.
- No `AudioObjectHasProperty` / `AudioObjectIsPropertySettable` seam.
- No new session-layer wrapper or state-machine changes.
- Three focused tests instead of a separate muter abstraction plus a wider integration matrix.
