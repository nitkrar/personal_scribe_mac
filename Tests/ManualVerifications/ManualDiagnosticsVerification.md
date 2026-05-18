# Manual Diagnostics Verification

1. Launch the app and open `Settings` → `Advanced`.
2. Confirm `Diagnostic logging` defaults to `Errors Only` and `Show live diagnostics overlay` is disabled.
3. Switch `Diagnostic logging` to `Verbose`, enable `Show live diagnostics overlay`, and verify a floating diagnostics panel appears.
4. Start and stop a recording, then confirm new diagnostics rows appear in the overlay while the app is running.
5. Switch `Diagnostic logging` back to `Errors Only` and verify the floating diagnostics panel closes immediately.
6. Trigger a session error and confirm a fresh line is appended to `<base dir>/logs/errors.log`.
7. With `Diagnostic logging = Verbose`, trigger normal non-error activity and confirm `<base dir>/logs/diagnostics.log` receives verbose entries while `errors.log` remains reserved for errors.
8. In `Settings` → `Advanced`, change `Log retention` to `3 days`, quit and relaunch the app, reopen `Advanced`, and confirm the value persists. Then set it to `0` and confirm the UI reads `Disabled`, meaning archive pruning is turned off while daily rotation still remains active.
9. With content present in `<base dir>/logs/errors.log` or `diagnostics.log`, backdate one current `.log` file to the previous local day (for example `touch -mt 202605172359 <base dir>/logs/errors.log`), relaunch the app, and confirm it rotates to `<base dir>/logs/errors.log.2026-05-17` while a fresh empty `errors.log` is recreated. Then set `Log retention` to `1 day`, create at least two dated archives for the same base log, relaunch, and confirm only the newest archive for that base log remains.
