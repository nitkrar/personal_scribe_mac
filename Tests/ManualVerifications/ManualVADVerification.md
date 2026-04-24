# Manual VAD Verification (#046 Stage A + Stage B)

Runbook for the VAD auto-stop feature. Assumes a fresh DMG with the bundled Silero CoreML model. Pill waveform is the primary Stage A signal; Stage B adds two opt-in preferences that surface through the ResponseCard (not the pill).

## MV-VAD-1 — Enabled happy path

1. Settings → General → Auto-stop: toggle **on**, threshold slider at **5.0s** (default).
2. Hotkey-record a sentence, stop talking.
3. **Expect:** pill transitions `.recording → .transcribing` automatically ~5s after you stop speaking. No manual hotkey press. Transcript lands in the active app via the normal paste path.

## MV-VAD-2 — Disabled preference is inert

1. Settings → General → Auto-stop: toggle **off**.
2. Hotkey-record a sentence, stop talking.
3. **Expect:** pill stays in `.recording` indefinitely. Session only ends when you manually stop (hotkey, pill tap, or Esc).

## MV-VAD-3 — Hold-to-record ignores VAD

1. Auto-stop **on**, threshold 5.0s.
2. Press-and-hold the hotkey, speak, then hold silently for 5s (well past the threshold).
3. **Expect:** pill stays on `.holdToRecord` the entire time. Release stops and transcribes as usual. VAD must not fire for the hold path — release is the sole stop signal.

## MV-VAD-4 — Manual stop during VAD countdown races safely

1. Auto-stop **on**, threshold 5.0s.
2. Hotkey-record, stop talking, immediately (within <1s) press the hotkey to stop.
3. **Expect:** exactly one transcript. No double-stop crash, no duplicate paste. (The race is actor-serialized; whichever stop wins, the other no-ops against `.transcribing` state.)

## MV-VAD-5 — Threshold slider change applies next session

1. Auto-stop **on**, threshold 5.0s (default).
2. Start recording (hotkey), while still recording open Settings → General and drag threshold to 2.5s.
3. Stop talking, wait.
4. **Expect:** current session auto-stops at the original ~5s (frozen-at-session-start). Start a new session; that one auto-stops at ~2.5s.

## Stage B preferences

Stage B adds two opt-in toggles inside Settings → General → Auto-stop (visible only when the master toggle is on). Both default **off** — shipped behavior is unchanged until the user turns them on.

- **Warn before stopping** — when on, VAD `.speechEnded` starts a 3.0s grace window. During grace, the ResponseCard shows `…stopping, speak to continue`. Three exits: timer elapses (fires), user resumes speaking (cancels + keeps recording), user presses the hotkey (fires immediately).
- **Show stop notification** — when on, after VAD-triggered auto-stop transitions to `.transcribing`, the ResponseCard briefly shows `Auto stopped. Update settings to change.` with a clickable link. Auto-dismisses at 2.0s OR when the next session starts.

## MV-VAD-6 — Warn enabled, notification off

1. Settings → General → Auto-stop: master on, **Warn before stopping: on**, **Show stop notification: off**.
2. Hotkey-record, speak a sentence, stop talking.
3. **Expect:** pill stays in `.recording` during the 3.0s grace. ResponseCard shows `…stopping, speak to continue`. After 3.0s uncancelled, session transitions to `.transcribing` normally. Card disappears.

## MV-VAD-7 — Warn enabled, speech resumes during grace

1. Same prefs as MV-VAD-6.
2. Hotkey-record, speak, stop talking for ~0.5s, then start talking again.
3. **Expect:** ResponseCard briefly showed `…stopping, speak to continue`, then disappeared when speech resumed. Session stays `.recording`. Keep talking; the session only ends when you either stop manually or go silent long enough for a fresh grace window to elapse.

## MV-VAD-8 — Warn off, notification on

1. Settings: master on, **Warn: off**, **Show stop notification: on**.
2. Hotkey-record, speak, stop talking.
3. **Expect:** instant auto-stop (Stage A behavior). Session transitions to `.transcribing`. ResponseCard shows `Auto stopped. Update settings to change.` for ~2s, then auto-dismisses.

## MV-VAD-9 — Notification link opens Settings

1. Same prefs as MV-VAD-8. Trigger auto-stop to see the notification.
2. While the card is visible, click the linked text `Update settings to change`.
3. **Expect:** Settings window opens. (Sub-tab focus on General is nice-to-have but not required in Stage B — user may see whatever sub-tab was last active.)

## MV-VAD-10 — Warn and notification both on

1. Settings: master on, **Warn: on**, **Show stop notification: on**.
2. Hotkey-record, speak, stop talking. Let the grace elapse.
3. **Expect:** during grace — card shows `…stopping, speak to continue`. After grace fires — card switches to `Auto stopped. Update settings to change.` for 2s. Then auto-dismisses.
4. **Variant:** repeat, but press the hotkey during the grace window. Session stops immediately. Notification does **NOT** fire — manual preemption is treated as a user-initiated stop, not a VAD-triggered one.
5. **Variant:** repeat, but resume speaking during grace. Grace cancels, card disappears. No notification fires (the stop didn't happen).

## Known gaps (carried from Stage A + Stage B scope limits)

- **Bundled-model load failure is a build-time invariant.** Guarded by `testFluidAudioVadProviderLoadsBundledModelAndProducesSession` in `PersonalScribeVADTests`, plus a debug-build `assertionFailure` in `FluidAudioVadProvider.init()`. If it somehow fires in production (malicious app-bundle tamper), VAD silently disables (recording still works); logged under category `session` at error level.
- **Esc semantics unchanged.** Esc during grace still true-discards the recording per #002 — it does NOT "cancel grace and keep recording." The two cancel paths during grace are (a) resumed speech (b) wait out the timer. This is deliberate to avoid overloading Esc.
- **Settings sub-tab focus.** Clicking the notification link opens Settings but may not force-select the General sub-tab if another was active. Promoting sub-tab routing into the unified-window model is deferred.
