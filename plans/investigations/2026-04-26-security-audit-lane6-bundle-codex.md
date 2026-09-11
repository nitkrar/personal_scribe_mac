# 2026-04-26 Security Audit — Lane 6 Bundle / Entitlements / Packaging (Codex)

> **Provenance note:** Codex's sandbox was fully read-only during the original task (Codex session `019dcbe7-42f5-7c02-8cf2-59d0767e4477`, task `task-mogc8v7i-l5xuh6`, completed 2026-04-26 22:31:43Z). Report content recovered verbatim from the codex job log by main session as a transcription artifact.

## 1. Threat-model framing

This lane is about the shipped bundle's trust and isolation posture. `PersonalScribeAppKit` is a single macOS app process unless `com.apple.security.app-sandbox` is present in its signed entitlements. SwiftPM dependencies such as `FluidAudio` and `GRDB` from `Package.swift` run in that same process, so they inherit the app's network, file-system, and IPC privileges. Hardened runtime helps with code-loading policy, but it does not restrict outbound network egress or local file access.

Observed posture from source plus the current `Ninimma.app` bundle:
- Hardened runtime is enabled (`scripts/package.py:432`, `scripts/package.py:433`; current bundle `codesign -dvv` shows `flags=0x10000(runtime)`).
- The only embedded entitlement is microphone access (`scripts/package.py:403`; current bundle `codesign -d --entitlements - Ninimma.app` shows only `com.apple.security.device.audio-input`).
- No sandbox entitlement is present anywhere in repo or bundle.
- `Info.plist` does not define `NSAppTransportSecurity`, `NSAllowsArbitraryLoads`, `CFBundleURLTypes`, or `LSUIElement`; default ATS behavior applies to ATS-aware APIs, but ATS is not a sandbox substitute.
- `NSMicrophoneUsageDescription` is present (`Ninimma.app/Contents/Info.plist:48`) and `NSPrincipalClass` is the default `NSApplication` (`Ninimma.app/Contents/Info.plist:42`).

## 2. Files audited

- `Ninimma.app/Contents/Info.plist`
- `scripts/package.py`
- `Package.swift`
- Entitlements search: `find . -name "*.entitlements" -not -path "*/.build/*" -not -path "*/.git/*"` returned no files.
- Read-only bundle checks: `codesign -dvv Ninimma.app`, `codesign -d --entitlements - Ninimma.app`, `codesign --verify --verbose=4 Ninimma.app`, and `find Ninimma.app/Contents -maxdepth 3 ...`

DMG composition from source is narrow: `scripts/package.py:455`, `scripts/package.py:457`, and `scripts/package.py:458` stage only `Ninimma.app` plus an `/Applications` symlink. The current bundle contents are only `Info.plist`, the executable, `PkgInfo`, the icon, and `_CodeSignature/CodeResources`; no `.DS_Store`, temp files, logs, or `.git` artifacts were found in the bundle tree.

## 3. Findings

1. **High** — `scripts/package.py:403`, `scripts/package.py:434`, `Package.swift:42`, `Package.swift:46`

   **What:** The shipped app is not sandboxed. No checked-in `.entitlements` file exists, and the packaging script generates only a temporary mic entitlement plist containing `com.apple.security.device.audio-input`. There is no `com.apple.security.app-sandbox` entitlement in source or in the current bundle.

   **Why:** `FluidAudio` and `GRDB` are linked into the main app process, so any third-party code runs with the app's full unsandboxed user-context privileges. Under this threat model, that means unrestricted outbound network egress and broad local file access are available to dependencies at runtime. Hardened runtime does not change this.

   **Mitigation:** Ship a checked-in entitlements plist, enable `com.apple.security.app-sandbox`, add only the minimum required sandbox exceptions, and re-audit every dependency under the sandboxed runtime.

2. **Medium** — `scripts/package.py:49`, `scripts/package.py:388`, `scripts/package.py:396`, `scripts/package.py:436`, `scripts/package.py:18`, `scripts/package.py:19`

   **What:** Packaging does not establish strong publisher provenance. The script prefers a local self-signed identity (`Nitkrar Dev`), falls back to ad-hoc signing (`-`), disables secure timestamps (`--timestamp=none`), and documents Gatekeeper bypass instructions (`right-click Open` or removing quarantine). The current bundle also shows `TeamIdentifier=not set`, and `codesign --verify` fails with `CSSMERR_TP_NOT_TRUSTED`.

   **Why:** A local/self-signed or ad-hoc signature provides weak trust semantics for a distributed DMG. Users end up bypassing platform trust checks instead of relying on a verifiable Developer ID + notarization chain, which weakens supply-chain trust.

   **Mitigation:** Sign release artifacts with a Developer ID Application certificate, enable timestamps, notarize the app or DMG, staple the notary ticket, and remove quarantine-bypass guidance from release instructions.

3. **Low** — `scripts/package.py:103`, `scripts/package.py:106`, `scripts/package.py:115`, `scripts/package.py:129`, `scripts/package.py:342`, `scripts/package.py:344`

   **What:** `--dmg` packaging does not force a `release` build. The examples present `scripts/package.py -d` as the GitHub Release path, but the default build config is `debug`, and symbol stripping only occurs for `release`.

   **Why:** This makes it easy to publish a DMG built from the debug configuration, preserving extra symbols and any debug-only behavior. It does not change sandboxing, but it weakens the predictability and minimization of the shipped artifact.

   **Mitigation:** Make `--dmg` imply `--config release`, or fail closed when `--dmg` is requested with any non-release build.

## 4. Coverage gaps

- No build, test, install, or DMG creation was performed per the lane constraints, so DMG findings are source-derived from `scripts/package.py` rather than from mounting a freshly built DMG.
- I did not inspect outbound network behavior dynamically. The unrestricted-egress conclusion is based on the absence of App Sandbox, not on traffic capture.
- `spctl` returned `internal error in Code Signing subsystem` on this machine, so Gatekeeper posture is inferred from package source plus `codesign` output rather than a clean `spctl` assessment.
- If another machine lacks the `Nitkrar Dev` certificate, the script will emit an ad-hoc-signed app instead; the exact signature type is environment-dependent, but both branches remain unsandboxed.
