- Grant permission through the Plan 04 UI flow.
- Instantiate `AVAudioCaptureService()`.
- Call `start()`.
- Speak for 2–3 seconds.
- Confirm yielded buffers report `sampleRate == 16_000`, `channelCount == 1`, and non-zero sample energy.
- Call `stop()`.
- Confirm the stream finishes normally once.
- Confirm a second `stop()` has no extra effect.

## Mute system audio while recording

- In Settings → General → Behavior, enable "Mute system audio while recording."
- Start media playback (Music.app or a browser video) so you can hear audio.
- Trigger a recording (hotkey tap). Confirm media silences the moment the pill shows recording, and resumes the moment recording stops.
- Disable the toggle. Repeat. Confirm media keeps playing throughout.
- Pre-mute the machine via the F10 mute key, then record with the toggle on. Confirm the machine stays muted after recording ends (prior state preserved).
- Start a recording with the toggle on, then quit the app via the menu-bar Quit item. Confirm audio resumes (prequit handler routes through `coordinator.stopIfActive()` → `SystemAudioMuter.restoreIfNeeded()`).
- With the toggle on, start a recording, then change the default output device mid-recording (e.g. plug in headphones). Confirm no stuck-mute state: system audio on the new route behaves per the F10 mute flag, which is route-independent.

## Input device changes mid-recording (#110)

Hardware harness without a headset: `NINIMMA_LIVE_DEVICE_TEST=1 swift test --filter LiveDeviceChangeTests` (changes the default input; don't run while recording in the app).

- Start recording on the built-in mic, connect AirPods mid-sentence, keep counting. Confirm recording continues on the AirPods.
- Put the AirPods in the case while counting. Confirm recording continues on the built-in mic with no "audio capture failed" error; expect about half a second lost per switch.
- Start another recording right after. Confirm it starts without an error.
- Confirm the left-pane microphone footer follows the device switches.
- If a recording receives exact digital silence (e.g. a Bluetooth mic's first activation), confirm the pill card shows "No audio from the microphone" within about 2 seconds.
