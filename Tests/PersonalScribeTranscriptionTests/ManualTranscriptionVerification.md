# Manual Transcription Verification

## Goal
Verify that `FluidAudioTranscriber` downloads the pinned Parakeet v2 model on first run and transcribes a short WAV end-to-end.

## Preconditions
- Apple Silicon
- macOS 14+
- Working network connection
- `SeshatConfig.testingBaseDirectoryOverride == nil`
- `ModelRegistry.parakeetTDT06Bv2.revision` is a real 40-character SHA

## Procedure
1. Remove any prior model under `~/Library/Application Support/Seshat/models/parakeet-tdt-0.6b-v2`.
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
7. Confirm failures log through `SeshatLogger(category: SeshatLogCategory.transcription)`.
8. Confirm there is no production `print()` path in the transcription module.

## Phase 1 Step 1.1b — Launch signposts

Signposts emitted under subsystem `com.nitkrar.seshat`, category `prepare`:
- `SessionCoordinator.prepareTranscriber`
- `FluidAudioTranscriber.performPrepare`
- `inference.loadModel`

### Trace capture procedure
1. Build and install the DMG to `/Applications/Seshat.app`.
2. Quit any running instance.
3. Capture a launch trace:
   ```
   xcrun xctrace record --template 'Logging' \
     --output /tmp/seshat-launch.trace \
     --launch -- /Applications/Seshat.app/Contents/MacOS/SeshatAppKit
   ```
4. Open `/tmp/seshat-launch.trace` in Instruments (os_signpost lane).
5. Confirm all three intervals are visible with plausible durations.
6. Record cold-launch durations below (milliseconds):

| Date | Build SHA | `prepareTranscriber` | `performPrepare` | `loadModel` | Notes |
|------|-----------|----------------------|------------------|-------------|-------|
| 2026-04-18 | 0969f59 | ~730-750 ms (cold), ~450 ms (warm) | under 1 s | under 1 s | Dogfood session; approximate visual read from Instruments os_signpost track. All three intervals visible. |

Phase 1 gate target: cold-launch `prepareTranscriber` < 5s (or outlier with recorded hypothesis). **Met on 2026-04-18.**
