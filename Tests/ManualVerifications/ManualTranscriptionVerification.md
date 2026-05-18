# Manual Transcription Verification

## Goal
Verify that `FluidAudioTranscriber` downloads the pinned Parakeet v2 model on first run and transcribes a short WAV end-to-end.

## Preconditions
- Apple Silicon
- macOS 14+
- Working network connection
- `AppConfig.testingBaseDirectoryOverride == nil`
- `ModelRegistry.parakeetTDT06Bv2.revision` is a real 40-character SHA

## Procedure
1. Remove any prior model under `~/Library/Application Support/personal_scribe/models/parakeet-tdt-0.6b-v2`.
2. Trigger `prepare()`.
3. Confirm progress `idle -> downloading -> finished`.
4. Feed a 16 kHz mono WAV speaking "hello world".
5. Confirm `TranscriptionResult.text` contains `hello world`.
6. Confirm the model directory contains:
   - `Preprocessor.mlmodelc/coremldata.bin`
   - `Encoder.mlmodelc/coremldata.bin`
   - `Decoder.mlmodelc/coremldata.bin`
   - `JointDecision.mlmodelc/coremldata.bin`
   - `parakeet_vocab.json`
7. Confirm failures emit through the unified diagnostics pipeline and appear in transcription diagnostics output.
8. Confirm there is no production `print()` path in the transcription module.

## Streaming dictation finalization (#056)

Prerequisites:
- a streaming ASR model is downloaded and valid
- a batch ASR model is active if you want to verify authoritative
  second-pass behavior

### MV-STREAM-TX-1 — streaming-only final
1. Activate a `Streaming Dictation` mode.
2. Turn `Authoritative second pass` OFF for that mode.
3. Record a short phrase and stop.
4. Confirm the final text in transcript history, clipboard, and optional
   stop-time paste matches the streaming model's final output.

### MV-STREAM-TX-2 — authoritative second pass wins when available
1. Leave the same mode active but turn `Authoritative second pass` ON.
2. Ensure a normal ASR model is active in `Settings → AI Models`.
3. Record the same phrase and stop.
4. Confirm transcript history and clipboard now use the batch
   authoritative final, even though the live StreamCard showed the
   streaming partials during capture.

### MV-STREAM-TX-3 — second pass unavailable falls back cleanly
1. Leave `Authoritative second pass` ON.
2. Remove the active batch ASR selection (or switch to a state where no
   plain ASR descriptor is active) while keeping the streaming ASR model
   valid.
3. Record and stop.
4. Confirm the session still completes and the final text falls back to
   the streaming final rather than erroring out.

### MV-STREAM-TX-4 — live cursor appends EOU chunks without stop-time duplicate
1. Turn `Live cursor streaming` ON globally or per-mode and ensure
   Ninimma has Accessibility access.
2. Focus a text field in another app.
3. Record a multi-utterance dictation with pauses long enough to trigger
   end-of-utterance commits while watching the insertion point.
4. Confirm text is appended during capture as utterances complete.
5. Stop the recording and confirm no extra duplicate final paste lands
   at stop.

## WhisperKit transcription (#095)

### MV-WHISPERKIT-OFFLINE — pre-staged tokenizer survives offline activation
1. While network is available, delete `Whisper Tiny (WhisperKit)` if it is
   already present, then download it again from `Settings → AI Models`.
2. Confirm the model leaf includes a `tokenizer/` subdirectory with
   `tokenizer.json` and `vocab.json`, and that each of
   `AudioEncoder.mlmodelc/`, `MelSpectrogram.mlmodelc/`, and
   `TextDecoder.mlmodelc/` contains `coremldata.bin`, `metadata.json`,
   `model.mil`, and `weights/weight.bin`.
3. Disable Wi-Fi and Ethernet.
4. Activate `Whisper Tiny (WhisperKit)` and record a short English
   phrase.
5. Confirm transcription completes successfully with no extra download
   or tokenizer fetch attempt.
6. Re-enable network after the run.

### MV-WHISPERKIT-NON-ENGLISH — multilingual Whisper path works end-to-end
1. Download and activate `Whisper Large v3 (WhisperKit, 626MB)` or, on
   lower-disk machines, `Whisper Small (WhisperKit, 216MB)`.
2. Record 5-10 seconds in a non-English language Whisper is expected to
   cover well (for example Japanese, Arabic, Hindi, or Vietnamese).
3. Confirm the final transcript lands in the spoken language rather than
   English transliteration or an empty result.
4. Repeat once with `Whisper Small English (WhisperKit, 217MB)` active
   and confirm the English-only row is not the recommended choice for
   this case.

## whisper.cpp transcription (#098)

For the checks below, `<base>` means Ninimma's current base directory.
By default that is `~/Library/Application Support/personal_scribe/`;
if you changed it in `Settings → Advanced`, use that location instead.

### MV-WHISPERCPP-4 — activation + transcription stay local after predownload
1. While network is available, download `Whisper Tiny (whisper.cpp)` from
   `Settings → AI Models`, and leave Activity Monitor's Network tab (or
   an equivalent network monitor) open for Ninimma.
2. Confirm `<base>/models/whispercpp-tiny/ggml-tiny.bin` exists before
   activation.
3. Click `Set Active` on `Whisper Tiny (whisper.cpp)` and immediately
   record a short known phrase such as `hello world from whisper cpp`.
4. Confirm the final transcript appears with reasonable accuracy.
5. Confirm activation does not trigger a fresh model download: the row
   may briefly show `Loading…`, but it must not go back to `Downloading`,
   and the app must reuse the already-downloaded `.bin` in place.

### MV-WHISPERCPP-5 — offline relaunch or switchback still works after predownload
1. While network is still available, leave `Whisper Tiny (whisper.cpp)`
   or another whisper.cpp row fully downloaded.
2. Disable Wi-Fi and Ethernet.
3. Relaunch Ninimma, or switch away to another downloaded ASR row and
   then back to the whisper.cpp row.
4. Activate the whisper.cpp row if needed and record a short phrase.
5. Confirm transcription completes successfully offline, the app does
   not re-enter `Downloading`, and no failure state appears as long as
   the `.bin` is still present under `<base>/models/whispercpp-*/`.
6. Re-enable network after the run.

## Model language hint transcription (#091)

- [ ] **MV-LANGHINT-3 — WhisperKit pinned hint takes effect:** choose a mode that explicitly pins `Whisper Tiny (WhisperKit)` (or another multilingual WhisperKit row), set that row's language picker to `Japanese (ja)`, then record a short Japanese clip. Confirm the final transcript is Japanese rather than English auto-detect output. Switch the picker back to `Auto-detect` after the check if you use the row for other manual cases.
- [ ] **MV-LANGHINT-4 — whisper.cpp pinned hint takes effect:** choose a mode that explicitly pins a multilingual whisper.cpp row, set its picker to `Japanese (ja)`, record a short Japanese clip, and confirm the final transcript is Japanese.
- [ ] **MV-LANGHINT-5 — Qwen3 pinned hint takes effect:** choose a mode that explicitly pins `Qwen3 ASR 0.6B`, set its picker to `Japanese (ja)`, record a short Japanese clip, and confirm the final transcript is Japanese rather than falling back to auto-detect.
- [ ] **MV-LANGHINT-6 — mode-default gate prevents descriptor-hint leak:** set `Whisper Tiny (WhisperKit)` to `Japanese (ja)` in `Settings → AI Models`, then switch to a mode whose ASR selection is `use default model` rather than a pinned descriptor. Record a short English clip while the default still resolves to that WhisperKit row. Confirm the transcript is English, not Japanese — the hint must be suppressed for the default-model path.
- [ ] **MV-LANGHINT-7 — Auto-detect clears back to normal behavior:** on a multilingual Whisper or Qwen3 row, switch the picker back to `Auto-detect`, record a short clip in a language the model normally auto-detects well, and confirm transcription still completes normally with no forced-language behavior.

## Phase 1 Step 1.1b — Launch signposts

Signposts emitted under subsystem `com.nitkrar.personal_scribe`, category `prepare`:
- `SessionCoordinator.prepareTranscriber`
- `FluidAudioTranscriber.performPrepare`
- `inference.loadModel`

### Trace capture procedure
1. Build and install the DMG to `/Applications/Ninimma.app`.
2. Quit any running instance.
3. Capture a launch trace:
   ```
   xcrun xctrace record --template 'Logging' \
     --output /tmp/personal_scribe-launch.trace \
     --launch -- /Applications/Ninimma.app/Contents/MacOS/PersonalScribeAppKit
   ```
4. Open `/tmp/personal_scribe-launch.trace` in Instruments (os_signpost lane).
5. Confirm all three intervals are visible with plausible durations.
6. Record cold-launch durations below (milliseconds):

| Date | Build SHA | `prepareTranscriber` | `performPrepare` | `loadModel` | Notes |
|------|-----------|----------------------|------------------|-------------|-------|
| 2026-04-18 | 0969f59 | ~730-750 ms (cold), ~450 ms (warm) | under 1 s | under 1 s | Dogfood session; approximate visual read from Instruments os_signpost track. All three intervals visible. |

Phase 1 gate target: cold-launch `prepareTranscriber` < 5s (or outlier with recorded hypothesis). **Met on 2026-04-18.**
