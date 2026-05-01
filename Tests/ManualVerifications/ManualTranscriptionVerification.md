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

### MV-STREAM-TX-4 — live cursor flag is runtime-inert in #056
1. Turn `Live cursor streaming` ON globally or per-mode.
2. Record into a text field while watching the insertion point.
3. Confirm no text is injected during capture.
4. Stop the recording and confirm the existing stop-time clipboard/paste
   path still runs exactly once.

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
