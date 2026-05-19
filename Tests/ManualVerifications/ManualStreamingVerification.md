# Manual Streaming Verification

## MV-STR-1

Start a streaming dictation session with live cursor enabled and speak three short utterances with clear pauses. Confirm each utterance pastes once into the target app as soon as the pause crosses the configured end-of-utterance silence threshold.

## MV-STR-2

Run a single-utterance streaming session. Confirm only one cursor paste occurs, then stop the session and confirm the final second-pass transcript still appears through the normal stop-time path.

## MV-STR-3

Start speaking, then stop the recording before the silence threshold is reached. Confirm no live cursor chunk was pasted for the unfinished utterance, but the final stop-time transcript still lands correctly.

## MV-STR-4

Open diagnostics after a normal streaming session and inspect the logs. Confirm you can find one `streaming_eou_emitted`, one `streaming_eou_received`, and one sink outcome line per utterance, with no `streaming_lcp_fallback` lines on the normal path.

## MV-STR-5

In Settings → General, change `Streaming dictation` end-of-utterance silence to a noticeably larger value. Run the default streaming mode and confirm end-of-utterance pastes now wait for the larger silence gap.

## MV-STR-6

Create or edit a streaming mode with a per-mode end-of-utterance override that differs from the General setting. Confirm that mode uses its override while another streaming mode without an override still follows the General setting.
