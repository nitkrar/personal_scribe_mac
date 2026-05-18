# Manual Diagnostics Verification

1. Launch the app and open `Settings` → `Advanced`.
2. Confirm `Diagnostic logging` defaults to `Errors Only` and the `Open Diagnostics Window` button is available.
3. Click `Open Diagnostics Window` and verify a floating diagnostics panel appears. Close it from the panel UI or with `Esc`, then confirm `Settings` → `Advanced` still shows the same `Diagnostic logging` value and no extra toggle/state changed.
4. Reopen the diagnostics window while `Diagnostic logging` remains `Errors Only`. Trigger a session error and confirm the window shows a new error row and a fresh line is appended to `<base dir>/logs/errors.log`.
5. Switch `Diagnostic logging` to `Verbose`, trigger normal non-error activity, and confirm the same diagnostics window now shows non-error rows while `<base dir>/logs/diagnostics.log` receives verbose entries and `errors.log` remains reserved for errors.
6. In `Settings` → `Advanced`, change `Log retention` to `3 days`, quit and relaunch the app, reopen `Advanced`, and confirm the value persists. Then set it to `0` and confirm the UI reads `Disabled`, meaning archive pruning is turned off while daily rotation still remains active.
7. With content present in `<base dir>/logs/errors.log` or `diagnostics.log`, backdate one current `.log` file to the previous local day (for example `touch -mt 202605172359 <base dir>/logs/errors.log`), relaunch the app, and confirm it rotates to `<base dir>/logs/errors.log.2026-05-17` while a fresh empty `errors.log` is recreated. Then set `Log retention` to `1 day`, create at least two dated archives for the same base log, relaunch, and confirm only the newest archive for that base log remains.
