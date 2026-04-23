# Manual VAD Verification (#046 Stage A)

Runbook for the VAD auto-stop feature. Assumes a fresh DMG with the bundled Silero CoreML model. Pill waveform is the primary user signal — no pill UI changes in Stage A.

## MV-VAD-1 — Enabled happy path

1. Settings → General → Auto-stop: toggle **on**, threshold slider at **2.5s** (default).
2. Hotkey-record a sentence, stop talking.
3. **Expect:** pill transitions `.recording → .transcribing` automatically ~2.5s after you stop speaking. No manual hotkey press. Transcript lands in the active app via the normal paste path.

## MV-VAD-2 — Disabled preference is inert

1. Settings → General → Auto-stop: toggle **off**.
2. Hotkey-record a sentence, stop talking.
3. **Expect:** pill stays in `.recording` indefinitely. Session only ends when you manually stop (hotkey, pill tap, or Esc).

## MV-VAD-3 — Hold-to-record ignores VAD

1. Auto-stop **on**, threshold 2.5s.
2. Press-and-hold the hotkey, speak, then hold silently for 5s (well past the threshold).
3. **Expect:** pill stays on `.holdToRecord` the entire time. Release stops and transcribes as usual. VAD must not fire for the hold path — release is the sole stop signal.

## MV-VAD-4 — Manual stop during VAD countdown races safely

1. Auto-stop **on**, threshold 2.5s.
2. Hotkey-record, stop talking, immediately (within <1s) press the hotkey to stop.
3. **Expect:** exactly one transcript. No double-stop crash, no duplicate paste. (The race is actor-serialized; whichever stop wins, the other no-ops against `.transcribing` state.)

## MV-VAD-5 — Threshold slider change applies next session

1. Auto-stop **on**, threshold 2.5s.
2. Start recording (hotkey), while still recording open Settings → General and drag threshold to 5.0s.
3. Stop talking, wait.
4. **Expect:** current session auto-stops at the original ~2.5s (frozen-at-session-start). Start a new session; that one auto-stops at ~5s.

## Known Stage A gaps (deferred)

- **No grace window.** VAD auto-stop is instant — Esc after auto-stop fires hits `.transcribing` (a no-op for cancel). Tracked for Stage B (about-to-stop sub-state, dogfood-gated).
- **Bundled-model load failure is silent.** If the bundled `.mlmodelc` can't be found (shouldn't happen in a released build), the feature silently disables. Settings toggle still appears normal; no pill error. Logged under category `session` at error level.
