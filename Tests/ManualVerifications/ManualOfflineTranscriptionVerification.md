# Manual Offline Transcription Verification

For the checks below, `<base>` means Ninimma's current base directory.
By default that is `~/Library/Application Support/personal_scribe/`;
if you changed it in `Settings → Advanced`, use that location instead.

- [ ] **MV-OFFLINE-1** Open the unified window and confirm a dedicated
  **Offline** sidebar item is present. Select it and confirm the tab
  shows the ASR model picker, speaker-detection toggle, and drop zone.
  The queue area is hidden until the first file is enqueued (verified
  separately in MV-OFFLINE-2).
- [ ] **MV-OFFLINE-2** Drag a supported audio file onto the drop zone.
  Confirm a queue row appears, processing starts, and a completed job's
  **View** action opens the transcript side pane with text loaded.
- [ ] **MV-OFFLINE-3** Drop three supported files at once. Confirm all
  three queue, only one is in flight at a time, and completion proceeds
  serially in enqueue order.
- [ ] **MV-OFFLINE-4** While a file is running, cancel it. Confirm the
  row moves to `cancelled` and the next queued file starts without
  needing to reopen the tab.
- [ ] **MV-OFFLINE-5** Start a live recording, then queue an offline
  file. Confirm the offline row stays queued while the live session is
  active, then begins once the live session ends.
- [ ] **MV-OFFLINE-6** Use the status-item menu → **Retranscribe Last
  Recording**. Confirm a toast reads `Re-transcribed → clipboard`,
  `pbpaste` returns the new text, and a new History row appears without
  reopening the window.
- [ ] **MV-OFFLINE-7** In `Transcriptions`, hover a row with persisted
  audio and click the re-transcribe icon. Confirm it produces the same
  toast + clipboard behavior as the menu-bar path and adds a new History
  row for the retranscribed result.
- [ ] **MV-OFFLINE-8** Click **Browse…** in the Offline tab. Confirm the
  file picker opens rooted at `<base>/recordings/` when that directory
  exists; on a fresh install with no recordings yet, the picker may fall
  back to the system default location.
- [ ] **MV-OFFLINE-9** Hover a History row with persisted audio and click
  the re-transcribe icon repeatedly. Confirm the button shows visible
  press feedback on click, stays in a busy state while the job is in
  flight, and repeated clicks do not create duplicate queued jobs for
  the same source file.
