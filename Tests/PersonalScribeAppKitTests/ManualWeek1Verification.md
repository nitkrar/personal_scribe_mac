# Manual Week 1 End-to-End Verification

Run this on a macOS 14+ Apple Silicon Mac after Plan 99 Step 4 passes.

1. `swift run PersonalScribeAppKit` - menu bar icon appears (SF Symbol "mic") in the status bar.
2. First-launch permission flow:
   - Click the menu bar icon -> popover opens.
   - Click "Grant microphone access" -> macOS system dialog appears.
   - Click Allow.
   - Popover state updates to "idle, ready to record".
3. First-run model download:
   - Watch the popover for model-download progress (indeterminate or percent).
   - Verify `~/Library/Application Support/personal_scribe/models/parakeet-tdt-0.6b-v2/` populates with:
     - `Preprocessor.mlmodelc`
     - `Encoder.mlmodelc`
     - `Decoder.mlmodelc`
     - `JointDecision.mlmodelc`
     - `parakeet_vocab.json`
   - Progress finishes -> UI shows "idle, ready to record".
4. Record a short utterance:
   - Click Record -> icon flips to red "mic.fill"; state label shows "recording".
   - Say "hello world" clearly.
   - Click Stop -> state label shows "transcribing" briefly, then "idle".
5. Verify transcript:
   - Popover shows the transcribed text ("hello world" or a close variant).
   - Click Copy -> open any app (TextEdit) and paste -> the transcript lands.
6. Quit the app. Relaunch.
   - Model is NOT re-downloaded (second-launch fast path works).
   - Permission is NOT re-prompted.

## Acceptance

Week 1 is complete when steps 1-6 all pass without manual intervention beyond the clicks specified. File any deviation as a follow-up issue, not a Week 1 blocker, unless the deviation prevents reaching step 5.

## Known Week 1 gaps (expected - NOT verification failures)

- No global hotkey. Must click the menu bar.
- No paste injection. Must click Copy then Cmd-V.
- No filler/punctuation cleanup. Raw Parakeet output.
- No notes database. Transcript is visible only in the popover until replaced.
- Clipboard clobbers whatever was on the pasteboard before Copy. (Week 2 adds save/restore.)
