# 2026-04-26 Security Audit — Cross-Lane Rollup & Action List

## TL;DR

7-lane dual-review audit (Claude + Codex per lane, independent passes) of Ninimma's data-exfiltration surface. **No active exfiltration in first-party code.** First-party `Sources/` has zero `URLSession` / network primitives, no analytics SDKs, no hardcoded secrets, no env reads beyond `PERSONAL_SCRIBE_BASE_DIR`, and audio buffers stay in-memory until handed to FluidAudio. **The single load-bearing weakness is OS-level isolation: the shipped app is not sandboxed**, so any current or future 3p dep runs with the user's full network + filesystem privileges. The most actionable findings are quick wins around backup/index exclusion, Logger privacy markers, and clipboard-restore defaults.

## Severity tally

| Severity | Count | Driving lanes |
|---|---|---|
| HIGH | 5 | 4 (×2), 5 (×2), 6 |
| MEDIUM | 11 | 1, 2 (×2), 3, 4 (×3), 5 (×2), 6, 7 |
| LOW | 10 | 1 (×3), 3, 4, 6 (×3), and metadata-leak duo from Lane 3 |
| INFO / clean | many | every lane has positive confirmations |

## Per-lane convergence

| Lane | Convergence | Notes |
|---|---|---|
| 1 Network egress | Strong; Codex went deeper | Codex audited FluidAudio internals → surfaced env-var registry redirection (Claude stayed first-party-only) |
| 2 3p dep boundary | Strong; orthogonal angles | Claude focused on what FluidAudio sees (path content); Codex on what controls paths (AppConfig env/Defaults override surface) |
| 3 Logs & telemetry | Strong on Logger; Codex caught more | Both flagged Logger `.public` design; Codex enumerated more callsites + 2 NEW metadata-leak sites |
| 4 Persistence | Strong | Both flagged backup/Spotlight/journal posture; Codex caught the orphan-sidecar gap |
| 5 IPC pasteboard/AX | Strong on memory leak; Codex caught more | Claude found memory snapshot leak; Codex independently caught it + system-clipboard indefinite retention + crash-window + AX-PID TOCTOU race |
| 6 Bundle & entitlements | Strong on no-sandbox; Codex broader on signing | Both agree no sandbox = main risk; Codex caught `--dmg` doesn't force release config |
| 7 Capture & secrets | Strong; one severity divergence | All 6 claims CONFIRMED; Codex flagged transcript-text persistence as MEDIUM, Claude as design-not-defect |

---

## Findings — HIGH

### H1. App is not sandboxed
**Lanes:** 6 (both reviewers); 4 (Claude noted as cross-cutting).
**Where:** No `.entitlements` file in repo. `scripts/package.py:403` injects only `com.apple.security.device.audio-input` at sign time. `codesign -d --entitlements - Ninimma.app` confirms only mic entitlement on the shipped bundle. Hardened runtime is enabled (`flags=0x10000(runtime)`) but doesn't restrict egress or filesystem access.
**Why:** FluidAudio + GRDB run in-process and inherit the app's full network + filesystem privileges. At the kernel level, any 3p dep (current or future supply-chain compromise) can read `~/`, write anywhere, post arbitrary network traffic. The "Audio never leaves your device" claim is enforced by source-level discipline only, not by the OS.
**Mitigation:** Adopt App Sandbox **paired with** an XPC-separated network helper so the main process holds user data and opts out of `network.client`, while the helper holds `network.client` and has no user data. Sandbox alone is insufficient because `network.client` is full-duplex (download AND upload) — see C1+C2 for full rationale.

### H2. Transcripts go into Time Machine
**Lane:** 4 (both reviewers).
**Where:** `Sources/PersonalScribeCore/Database/AppDatabase.swift:41-43` opens `<base>/recordings/transcripts.sqlite`. Repo-wide grep returns zero `URLResourceKey.isExcludedFromBackup` / `setResourceValues` calls.
**Why:** Plaintext transcript history (text, timestamps, durations) is backup-eligible by default → entire transcript history hits user's Time Machine destination + iCloud backups for any third-party agent that mounts those volumes.
**Mitigation:** Set `URLResourceValues.isExcludedFromBackup = true` on the base directory and on `transcripts.sqlite` during storage bootstrap. Add regression coverage so new persistence paths inherit the policy.

### H3. Spotlight indexes workflow-modes.json
**Lane:** 4 Claude.
**Where:** Base directory has no `.metadata_never_index` marker. `workflow-modes.json` stores mode names + system prompts at the base-directory root.
**Why:** Mode names + system prompts (which can be quite specific to user workflow) are indexed by Spotlight, queryable by other apps with full-disk access.
**Mitigation:** Drop `.metadata_never_index` (empty file) at base directory creation time. Cheap.

### H4. Default-off clipboard restore → transcripts left on system pasteboard indefinitely
**Lanes:** 5 Codex H#1 (NEW vs Claude framing).
**Where:** `Sources/PersonalScribeAppKit/Output/ClipboardBatchOutput.swift:76-85` writes transcript to `NSPasteboard.general` unconditionally. `Sources/PersonalScribeAppKit/Settings/ClipboardRestoreEnabledPreference.swift:18-35` defaults `false`.
**Why:** Fresh installs leave transcripts on the system clipboard with no auto-clear. Sniffable by any other local app that polls `NSPasteboard.general`. Distinct from Lane 5 Claude's L5-1 (in-memory snapshot leak) — same code path, two exposures.
**Mitigation:** Make `ClipboardRestoreEnabled` default to `true` with a conservative delay (current default is 3.0s). Or gate indefinite retention behind explicit opt-in with a privacy warning in Settings.

### H5. Crash during restore window leaves transcript on clipboard with no recovery
**Lane:** 5 Codex H#2 (NEW).
**Where:** `Sources/PersonalScribeAppKit/Output/ClipboardBatchOutput.swift:41-47, 94-99`. Restore is a best-effort in-process timer; pre-transcript snapshot is in-memory only.
**Why:** If app quits/crashes/sleeps long enough during the restore window, the transcript stays on `NSPasteboard.general` and the original clipboard is unrecoverable on next launch.
**Mitigation:** Persist a minimal write-marker (encrypted or just a token + DB row) so next launch can clear our pasteboard write if it still owns the changeCount. Or document restore as best-effort and avoid clipboard for sensitive content.

---

## Findings — MEDIUM

### M1. `PersonalScribeLogger` forces `privacy:.public` on every value
**Lanes:** 3 (both); 4 Codex echoed it.
**Where:** `Sources/PersonalScribeCore/Logger.swift:18-20, 28-30, 39-42`. `renderedMessage`, `renderedFile`, `error.localizedDescription` all marked `.public`. Three reviewers in two lanes converged.
**Why:** Today's callers happen to log non-sensitive values, but the wrapper bakes in that any future caller passing transcript text, recording paths, or filesystem errors will land non-redacted in unified logs (Console.app, sysdiagnose).
**Mitigation:** Default to `.private`; opt-in `.public` only for known-safe fields (event names, enum cases, counter values). Map errors to redacted enums before logging.

### M2. `BaseDirectoryMigrator` logs full filesystem paths
**Lane:** 3 (both).
**Where:** `Sources/PersonalScribeCore/BaseDirectoryMigrator.swift:101, 207-210`. Logs `legacy.path → current.path` (which expand to `/Users/<unixname>/...`) plus `error.localizedDescription` via `NSLog` on rollback.
**Why:** macOS short-name leak into unified log; rollback failures may echo more filesystem detail. Compounds M1.
**Mitigation:** Log fixed event names or hashed tokens; never feed filesystem errors straight into `.public` logs.

### M3. AX-PID check-to-Cmd+V post is a TOCTOU race
**Lane:** 5 Codex M#4 (NEW).
**Where:** `Sources/PersonalScribeAppKit/Output/ClipboardBatchOutput.swift:124-136, 139-156, 173-203`.
**Why:** AX-checks focused PID, then posts untargeted global Cmd+V. If focus shifts in the gap (Spaces switch, Mission Control, modal popup, sleep wake), the transcript pastes into a different window than the one vetted.
**Mitigation:** Re-read focused PID immediately before posting; abort on change. Or hold target identity stable by activating the front app first.

### M4. Pasteboard snapshot accumulation when restore disabled
**Lanes:** 5 Claude L5-1 + 5 Codex M#3 (convergence).
**Where:** `ClipboardBatchOutput.swift:78-79` calls `captureTransientSnapshot()` *before* checking `ClipboardRestoreEnabledPreference`. `maybeScheduleRestore` short-circuits at line 95 without calling `discardSnapshot(handle)`. `PasteboardSnapshotService.deepCopy` copies every NSPasteboardItem representation.
**Why:** With restore disabled (the default), each dictation leaks the user's pre-recording clipboard (passwords, 2FA codes, chat snippets) into `transientSnapshots[]` for the lifetime of the app.
**Mitigation:** Gate `captureTransientSnapshot()` on `restoreEnabled`, OR call `discardSnapshot(handle)` on the early-return branch.

### M5. GRDB journal mode not pinned; siblings not chmod 0600
**Lane:** 4 (both).
**Where:** `Sources/PersonalScribeCore/Database/AppDatabase.swift:57` opens with bare `DatabaseQueue(path:)`. Only `transcripts.sqlite` itself is chmodded 0600 (`AppDatabase.swift:192-200`).
**Why:** Journal mode defaults to DELETE → on crash, `-journal` siblings exist with default permissions and contain plaintext transcript page deltas.
**Mitigation:** Explicitly configure journal strategy. Chmod 0600 on all SQLite artifacts (`-journal`, `-wal`, `-shm` if WAL is selected). Cleanup stale siblings at startup.

### M6. `BaseDirectoryMigrator.migrateFromLegacyBrandDirectoryIfNeeded()` is unwired
**Lane:** 4 (both).
**Where:** `Sources/PersonalScribeCore/BaseDirectoryMigrator.swift:88` — defined, no caller in `Sources/`.
**Why:** Users upgrading from the old `Seshat/` build retain a second on-disk copy at `~/Library/Application Support/Seshat/` indefinitely.
**Mitigation:** Wire the call at startup before opening current persistence; verify source path is gone after move.

### M7. `workflow-modes.json` written without explicit permissions
**Lane:** 4 (both).
**Where:** `Sources/PersonalScribeSession/WorkflowMode/WorkflowModeStore.swift:63-72` uses `Data.write(..., .atomic)`.
**Why:** Inherits umask 0644 on the non-sandboxed app. Holds workflow metadata: `activeModeID`, custom recipes, processor/capture/output-sink config. Also: `BaseDirectoryMigrator.migrate(to:)` only moves `ManagedDirectory` subdirectories, so this root-level sidecar would strand on a future base-dir migration.
**Mitigation:** `chmod 0600` after save. Move sidecar under a managed subdirectory, OR teach migrator to carry root-level files.

### M8. Bundle signing posture is weak
**Lane:** 6 (both, with Codex broader).
**Where:** `scripts/package.py:49, 388, 396, 436` — prefers `Nitkrar Dev` self-signed, falls back to ad-hoc (`-`), `--timestamp=none`, and documents Gatekeeper-bypass instructions. `codesign --verify` returns `CSSMERR_TP_NOT_TRUSTED`. `TeamIdentifier=not set`.
**Why:** Users bypass platform trust checks → quarantine-bypass becomes habitual → real future supply-chain compromise wouldn't trigger any user-side signal.
**Mitigation:** Move to Developer ID Application + notarization + stapling when preparing for distribution. Remove quarantine-bypass guidance from docs.

### M9. Transcript text persistence — at-rest protection decision
**Lane:** 7 Codex (severity divergence with Claude).
**Where:** `transcripts.sqlite` `text` column at `AppDatabase.swift:41-43`, `TranscriptsMigrator.swift:26-30`.
**Why:** Documented Phase-3 design (notes = transcripts), but it is sensitive derived content on disk protected only by chmod 0600 + (eventually) sandbox + (TBD) backup-exclusion. Codex flagged as MEDIUM ("decide whether 0600 is sufficient or stronger at-rest"), Claude treated as design-not-defect.
**Mitigation:** Make a deliberate decision: stay with chmod 0600 + backup-exclusion + sandbox, OR adopt SQLCipher with passphrase from Keychain. Document the choice + retention/deletion behavior.

### M10. AppConfig env/Defaults can redirect FluidAudio + GRDB paths
**Lane:** 2 Codex.
**Where:** `Sources/PersonalScribeCore/Storage/AppConfig.swift:101-102` reads `PERSONAL_SCRIBE_BASE_DIR` env. `AppStorageLocator` fans this out to `transcripts.sqlite` path + model cache paths used by FluidAudio.
**Why:** A local actor or a UserDefaults-injecting compromise can redirect where FluidAudio loads/saves models AND where the DB lives. Combined with H1 (no sandbox), this widens the attack surface.
**Mitigation:** Strip the env override in shipped builds (only allow during dev). Or restrict it to debug configs.

### M11. `OfflineDiarizerManager.prepareModels` parent-models-dir scope
**Lane:** 2 Claude F-2.
**Where:** `Sources/PersonalScribeTranscription/Adapters/FluidAudioOfflineDiarizerAdapter.swift:138-140`.
**Why:** Passes the parent `models/` directory rather than a per-repo scoped subdirectory like every other FluidAudio adapter. Wider write authority than necessary. Raises blast-radius if FluidAudio's diarizer changes its internal folder selection.
**Mitigation:** Pass `models/<repoFolderName>/` like the other adapters.

---

## Findings — LOW

| ID | Lane | Where | Mitigation |
|---|---|---|---|
| L1 | 1 (both) | `ModelDescriptor.resolveURL` is dead code — no callers | Delete it. Latent path-injection if anyone wires it to user input. |
| L2 | 1 Codex | FluidAudio downloader honors `REGISTRY_URL` / `MODEL_REGISTRY_URL` / `http_proxy` / `https_proxy` env vars | Assert `ModelRegistry.baseURL == "https://huggingface.co"` at startup; ignore env overrides in shipped builds. |
| L3 | 1 Codex INFO | Live ASR path GETs HuggingFace tree-listing APIs + JSON metadata (`parakeet_vocab.json`), not just binaries | Update threat-model wording. Or replace recursive listing with a baked file manifest. |
| L4 | 3 (both, severity divergence) | `Sources/PersonalScribeAudio/AudioEngineDriver.swift:130` `print(uid)` — hardware UID on warning path | Drop the UID; log only that persisted device was unavailable. (Codex MEDIUM, Claude LOW.) |
| L5 | 3 Codex | `MenuBarSceneModel.swift:122` logs `text.count` | Transcript-length metadata leak; log fixed level or omit. |
| L6 | 3 Codex | `PillOverlayPresenter.swift:481` logs `panel.frame` | Screen-geometry metadata; log only state changes. |
| L7 | 4 Codex | `TranscriptRepository.delete` only removes row; leaves any optional audio sidecars (`#069`) | Bind audio-sidecar lifecycle to transcript CRUD when the feature lands. Currently latent. |
| L8 | 6 Claude | `--deep` deprecated codesign flag | Benign today (flat bundle); remove before adding helpers/frameworks. |
| L9 | 6 Codex | `--dmg` doesn't force `--config release` | Make `--dmg` imply release, or fail if requested with debug. |
| L10 | 6 Claude | `--timestamp=none` blocks future notarization | Remove when moving to Developer ID. |

---

## Action list — what to work on

Grouped by effort × impact. Read top-to-bottom for biggest bang per minute.

### Quick wins (≤30 min each, do these first)

- [ ] **A1.** Mark `transcripts.sqlite` (and the recordings dir) as `URLResourceKey.isExcludedFromBackup`. Storage bootstrap. Closes **H2**.
- [ ] **A2.** Drop `.metadata_never_index` (empty file) at base-dir creation time. Closes **H3**.
- [ ] **A3.** Flip `ClipboardRestoreEnabledPreference.default` from `false` → `true`. Closes **H4** for fresh installs. Update tests + manual-verification runbook.
  - **Decision:** default-on. Accept that this regresses the deliberate-OFF mitigation for #072 (silent-drop-into-cursorless-surface) for the security win on H4.
  - **Follow-up to explore (B-tier candidate):** feasibility of paste-success detection inside `ClipboardBatchOutput` so restore can be deferred when we couldn't confirm the paste landed (e.g., `.clipboardOnly` outcome, AX untrusted, focus-in-self). This would let default-on coexist with #072 mitigation. Sketch first, scope later.
  - **Mitigation for users who toggle OFF:** add a transient privacy disclosure (Settings sheet / inline banner) shown when the user explicitly switches restore from on → off, explaining "transcripts will stay on your clipboard until you copy something else." One-shot, dismissable, not on every launch. Ensures the persistent-clipboard tradeoff is an informed opt-in.
- [ ] **A4.** Delete `ModelDescriptor.resolveURL(for:)`. Closes **L1**.
- [ ] **A5.** `chmod 0600` on `workflow-modes.json` after `Data.write`. Closes **M7**.
- [ ] **A6.** `chmod 0600` SQLite journal/WAL/SHM siblings on creation/cleanup at startup. Part of **M5**.
- [ ] **A7.** Wire `BaseDirectoryMigrator.migrateFromLegacyBrandDirectoryIfNeeded()` at app startup. Closes **M6**.
- [ ] **A8.** Replace `print(uid)` in `AudioEngineDriver.swift:130` with central logger; drop UID from message. Closes **L4**.
- [ ] **A9.** Remove `text.count` from `MenuBarSceneModel.swift:122` log. Closes **L5**.
- [ ] **A10.** Remove `panel.frame` from `PillOverlayPresenter.swift:481` log. Closes **L6**.
- [ ] **A11.** `--dmg` flag in `scripts/package.py` should imply or require `--config release`. Closes **L9**.
- [ ] **A12.** Remove quarantine-bypass instructions from `scripts/package.py:18-19` README/docstring. Hygiene for **M8**.
- [ ] **A13.** `discardSnapshot(handle)` on the early-return path when `restoreEnabled == false` in `ClipboardBatchOutput.deliverBatch`. Closes **M4**.

### Medium projects (1-3 hr each)

- [ ] **B1.** **Logger refactor.** Default `.private` for interpolated values; opt-in `.public` only for known-safe fields. Audit all callsites under `Sources/`. Tests for each new caller's privacy posture. Closes **M1**, **M2** (with B2), **L4** (cleaner).
- [ ] **B2.** **Path-redacting log helper.** Anywhere `BaseDirectoryMigrator` (or future filesystem code) logs a path, route through a helper that returns either a fixed event name or `~/.../<segment>` rather than full path. Closes **M2**.
- [ ] **B3.** **`OfflineDiarizerManager.prepareModels` scope tightening.** Pass `models/<repoFolderName>/` like peer adapters. Closes **M11**.
- [ ] **B4.** **FluidAudio registry pinning.** Assert at app startup: `ModelRegistry.baseURL == "https://huggingface.co"`; refuse to download if env vars set in production builds. Closes **L2**.
- [ ] **B5.** **AX-PID re-check before Cmd+V post.** Re-read focused PID immediately before `CGEventPost`; abort on change. Add runtime test for focus churn. Closes **M3**.
- [ ] **B6.** **Pasteboard write-marker for crash recovery.** Persist a small DB row noting "we wrote transcript X to pasteboard at time T with changeCount N". On next launch, if `changeCount` still matches, clear our write. Closes **H5**.
- [ ] **B7.** **Restrict `PERSONAL_SCRIBE_BASE_DIR` to debug builds only.** Read it only when `#if DEBUG` or via a build-config flag. Closes **M10**.
- [ ] **B8.** **Settings privacy copy.** Add explicit "transcripts are stored in plaintext on this Mac, protected by file permissions only" disclosure near Phase-3 UI. Supports **M9**.
- [ ] **B9.** **GRDB journal-mode pin.** Explicitly select journal mode in `AppDatabase.swift` (DELETE for simplicity, or WAL with explicit cleanup). Document the choice. Closes rest of **M5**.

### Foundational (multi-day, deferred but tracked)

- [ ] **C1 + C2 (paired commitment).** **Adopt App Sandbox AND process-separate the downloader into an XPC helper.** These are not independent — `network.client` is symmetric (full-duplex outbound: download AND upload). Sandbox alone (C1) doesn't solve the threat model; it just reshapes which surface holds the symmetric network entitlement. The fix is data-flow isolation, kernel-enforced via two sandboxed processes:
  - **Main app (Ninimma)**: declares `com.apple.security.app-sandbox` + audio capture / AX / files-via-bookmarks, but **NO** `com.apple.security.network.client`. Holds all user data (recordings, transcripts, AX, env). Kernel denies socket creation for FluidAudio or any other in-process 3p code → cannot exfiltrate.
  - **`NinimmaModelDownloader.xpc`**: sandboxed; entitled with `network.client` + write access to the model cache directory only. Has no AX, no recordings, no transcripts, no env. Hosts FluidAudio's `ModelManager.download()`. Even a fully-compromised downloader can leak at most "we asked for model X" plus the model bytes themselves — neither is user data.
  - Together they close **H1** at the kernel level AND close the FluidAudio runtime trust gap regardless of any future dep behavior.
  - **Doing only C1** is a half-measure: it just gates whether the main app has unrestricted network or none, neither of which fits the threat model.
  - **Doing only C2** (process split without sandboxing both halves) is honor-system: a 3p library running anywhere outside the sandbox can still reach the network because there's no kernel boundary.
  - Implementation cost: ~2-3 days. FluidAudio's API is already structured as `download → cache on disk → load from disk`, so the seam exists. Wire entitlements through `scripts/package.py`. Re-test every feature under sandbox. **Proposed earlier as "Layer 1 + process separation"**; user-deferred pending quick-wins triage.
- [ ] **C3.** **Transcript at-rest protection decision.** Choose: (i) chmod 0600 + sandbox + backup-exclusion (status-quo plus A1 + C1+C2), or (ii) SQLCipher passphrase via Keychain. Document. Resolves **M9** + Codex/Claude severity disagreement.
- [ ] **C4.** **Developer ID + notarization.** Pre-distribution. Closes **M8** + **L10**. Requires (i) a Developer ID Application certificate, (ii) notarytool wiring in `scripts/package.py`, (iii) stapler step. Removes the quarantine-bypass user training.

### Threat-model documentation (no code change)

- [ ] **D1.** Update threat-model doc: "model-binary downloads from HuggingFace" → "HuggingFace tree-listing + metadata + binary downloads". Closes **L3**.
- [ ] **D2.** Document the deliberate Codex/Claude severity disagreement on `print(uid)` (**L4**) and on transcript-text persistence (**M9**). Either re-rank or note design intent.

---

## Dual-review value summary

The audit ran 14 reviewers (7 lanes × Claude + Codex), with one extra Codex reviewer for 3p-pin which was a no-op since deps are already exact-pinned (FluidAudio `0.13.6`, GRDB `7.10.0`).

**Findings the dual review caught that single review would have missed:**
- **H4 + H5** (Lane 5 Codex): system-clipboard indefinite retention + crash-during-restore-window. Claude found the in-memory snapshot leak; Codex found the system-pasteboard exposure on the same code path. Two distinct exposures from one bug.
- **L2 + L3** (Lane 1 Codex): FluidAudio honors registry-redirection env vars; HuggingFace API listings + metadata are also fetched. Claude stayed first-party-only per the original brief; Codex went into `.build/checkouts/FluidAudio/` and surfaced both.
- **L5 + L6** (Lane 3 Codex): `text.count` + `panel.frame` metadata leaks. Claude focused on Logger.swift design; Codex enumerated callsites systematically.
- **L7** (Lane 4 Codex): `TranscriptRepository.delete` leaves audio sidecars. Claude focused on the persistence-layer schema; Codex traced the deletion path.
- **L9** (Lane 6 Codex): `--dmg` doesn't force release config.
- **M3** (Lane 5 Codex): AX-PID TOCTOU.
- **M10** (Lane 2 Codex): AppConfig env override surface.

**Severity divergences** (worth a deliberate decision):
- **L4** `print(uid)` — Claude LOW, Codex MEDIUM.
- **M9** transcript-text persistence — Claude design-not-defect, Codex MEDIUM.

---

## Coverage gaps & runtime caveats

- **FluidAudio + GRDB internals** were only audited at the API boundary, with one exception: Lane 1 Codex retry went deep into FluidAudio (`.build/checkouts/FluidAudio/Sources/FluidAudio/ModelRegistry.swift`, `DownloadUtils.swift`, `AsrModels.swift`). All other deep-dep behavior is still trusted-by-pin, not audited.
- **No runtime verification.** Static-only audit. No Little Snitch capture, no `lsof` of the running process, no behavioral confirmation of clipboard-restore timing under sleep/App Nap, no verification of the AX-TOCTOU hypothesis.
- **`Tests/`** out of scope.
- **Bundled `.mlmodelc` artifacts** are binary; can't statically audit for embedded telemetry or model behavior.
- **Codex runtime was unreliable** on this run: 5 of 11 codex dispatches succeeded outright; 2 hit read-only sandbox (Lanes 5 + 6 — recovered from job logs); 4 wedged or queued indefinitely (recovered via wave-2 retries). Fully retried with strict heartbeat + checklist briefs landed all 7 lanes.
- **Pin agent (#15)** wedged on Santa from a temp-dir manifest binary. Moot — Lane 2 already verified deps are exact-pinned.

---

## Reproducibility — per-lane reports

- [Lane 1 Network — Claude](2026-04-26-security-audit-lane1-net-claude.md)
- [Lane 1 Network — Codex retry](2026-04-26-security-audit-lane1-net-codex.md)
- [Lane 2 3p boundary — Claude](2026-04-26-security-audit-lane2-3p-claude.md)
- [Lane 2 3p boundary — Codex](2026-04-26-security-audit-lane2-3p-codex.md)
- [Lane 3 Logs — Claude](2026-04-26-security-audit-lane3-logs-claude.md)
- [Lane 3 Logs — Codex retry](2026-04-26-security-audit-lane3-logs-codex.md)
- [Lane 4 Persistence — Claude](2026-04-26-security-audit-lane4-persist-claude.md)
- [Lane 4 Persistence — Codex retry](2026-04-26-security-audit-lane4-persist-codex.md)
- [Lane 5 IPC — Claude](2026-04-26-security-audit-lane5-ipc-claude.md)
- [Lane 5 IPC — Codex (recovered)](2026-04-26-security-audit-lane5-ipc-codex.md)
- [Lane 6 Bundle — Claude](2026-04-26-security-audit-lane6-bundle-claude.md)
- [Lane 6 Bundle — Codex (recovered)](2026-04-26-security-audit-lane6-bundle-codex.md)
- [Lane 7 Capture — Claude](2026-04-26-security-audit-lane7-capture-claude.md)
- [Lane 7 Capture — Codex retry-2 (recovered)](2026-04-26-security-audit-lane7-capture-codex.md)
