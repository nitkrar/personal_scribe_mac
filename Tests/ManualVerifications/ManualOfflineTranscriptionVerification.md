# Manual Offline Transcription Verification

The offline-file transcription surfaces span the unified window, the
menu bar, and the shared response-card toast path. Unit tests cover the
view models and coordinator logic; use this runbook for the runtime-only
UI and end-to-end flow checks.

- [ ] **MV-OFFLINE-1** Open the unified window and confirm a new sidebar
  item labeled `Offline Files` is present. Click it and verify the tab
  shows the model picker, `Enable diarization` toggle, drop zone, and
  queue list.
- [ ] **MV-OFFLINE-2** Drag a supported `.wav` file onto the drop zone.
  Confirm a row appears in the queue, advances through queued/in-flight
  progress, and finishes as completed. Click `View` and verify the side
  pane opens on the right with selectable transcript text.
- [ ] **MV-OFFLINE-3** Drop or pick three supported files at once.
  Confirm all three appear in the queue, only one row is ever `in
  flight` at a time, and each file completes in serial order.
- [ ] **MV-OFFLINE-4** Queue at least two files, then cancel the active
  one while it is running. Confirm that row transitions to `Cancelled`
  and the next queued file starts automatically.
- [ ] **MV-OFFLINE-5** Start a live recording, then drop a supported file
  into `Offline Files`. Confirm its row stays queued with the waiting
  state until the live session ends, then begins processing without
  re-adding the file.
- [ ] **MV-OFFLINE-6** With at least one recorded transcript that still
  has audio, open the status-item menu and click `Retranscribe Last
  Recording`. Confirm a response-card toast reads `Re-transcribed →
  clipboard`, `pbpaste` returns the new transcript text, and a fresh row
  appears in the `Transcriptions` tab.
- [ ] **MV-OFFLINE-7** In the `Transcriptions` tab, hover a row that has
  recorded audio and confirm a trailing re-transcribe icon appears next
  to the trash action. Click it and verify the same toast appears, the
  clipboard updates, and a new transcript row is added without mutating
  the original row.
- [ ] **MV-OFFLINE-8** Click `Browse…` in `Offline Files` and confirm the
  picker opens in Ninimma's `<base>/recordings/` directory when it
  exists, rather than defaulting to `~/Documents`.
