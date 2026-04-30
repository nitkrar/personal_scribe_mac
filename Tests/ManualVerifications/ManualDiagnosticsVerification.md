# Manual Diagnostics Verification

1. Launch the app and open `Settings` → `Advanced`.
2. Confirm `Diagnostic logging` defaults to `Errors Only` and `Show live diagnostics overlay` is disabled.
3. Switch `Diagnostic logging` to `Verbose`, enable `Show live diagnostics overlay`, and verify a floating diagnostics panel appears.
4. Start and stop a recording, then confirm new diagnostics rows appear in the overlay while the app is running.
5. Switch `Diagnostic logging` back to `Errors Only` and verify the floating diagnostics panel closes immediately.
6. Trigger a session error and confirm a fresh line is appended to `<base dir>/logs/errors.log`.
7. With `Diagnostic logging = Verbose`, trigger normal non-error activity and confirm `<base dir>/logs/diagnostics.log` receives verbose entries while `errors.log` remains reserved for errors.
