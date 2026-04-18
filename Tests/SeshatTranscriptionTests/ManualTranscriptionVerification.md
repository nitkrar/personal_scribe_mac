# Manual Transcription Verification

## Goal
Verify that `FluidAudioTranscriber` downloads the pinned Parakeet v2 model on first run and transcribes a short WAV end-to-end.

## Preconditions
- Apple Silicon
- macOS 14+
- Working network connection
- `SeshatConfig.testingBaseDirectoryOverride == nil`
- `ParakeetArtifact.modelRevision` is a real 40-character SHA

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
