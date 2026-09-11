# Security audit — Lane 6: Bundle, entitlements, packaging (Claude)

Date: 2026-04-26
Reviewer: Claude (independent of Codex Lane 6)
Scope: shipped Ninimma.app trust posture — sandbox, entitlements, signing, hardened runtime, DMG composition, Info.plist permissions
Mode: READ-ONLY. No build, no sign, no test.

---

## 1. Threat-model framing

The app bundle's trust posture is the outermost runtime cap on what every dependency
(FluidAudio, GRDB, Foundation/URLSession callers, anything statically linked) is allowed to
do at runtime — independent of source-level audit.

Three macOS controls bound this surface:

1. **App sandbox** (`com.apple.security.app-sandbox` entitlement). When asserted, the
   kernel containerizes the process: filesystem access is jailed, network egress is gated
   per-direction by `com.apple.security.network.client` / `network.server`, IPC is
   restricted, and TCC-protected resources require sub-entitlements. **Without the
   sandbox entitlement the app runs as an unsandboxed user-process — the kernel imposes no
   network egress restriction at all.**
2. **Hardened Runtime** (`codesign --options runtime`). Hardens the process against
   library injection (`DYLD_INSERT_LIBRARIES`), unsigned-code execution
   (`com.apple.security.cs.allow-unsigned-executable-memory`), and JIT abuse. Does **not**
   sandbox or restrict egress; orthogonal to (1).
3. **TCC** (Transparency, Consent, Control). User-prompted runtime grants for Mic, Camera,
   Input Monitoring, Accessibility, etc. Backstop for resources that require user consent
   regardless of sandbox state. Bypassing TCC requires kernel exploit; not in scope.

**Question this lane answers**: when Ninimma.dmg lands on a user's Mac and they launch it,
what does the OS allow it (and any embedded 3p code) to do? Specifically — can FluidAudio,
GRDB, or any other dep make arbitrary outbound HTTPS requests, read arbitrary files in
$HOME, write to /tmp, spawn subprocesses, etc., at the trust-posture layer?

---

## 2. Files audited

| Path | Role |
| --- | --- |
| `Ninimma.app/Contents/Info.plist` (XML, 56 lines) | Shipped bundle Info.plist (committed artifact) |
| `Ninimma.app/Contents/_CodeSignature/CodeResources` | Sealed-resource manifest (verified via `codesign -dvvv`) |
| `Ninimma.app/Contents/MacOS/PersonalScribeAppKit` | Single Mach-O thin (arm64), 24.3 MB; runtime flag confirmed (`flags=0x10000(runtime)`) via `codesign -dvvv` |
| `Ninimma.app/Contents/Resources/Ninimma.icns` | Hand-authored app icon |
| `Ninimma.app/Contents/PkgInfo` | 8 bytes; `APPL????` marker |
| `scripts/package.py` (552 lines) | Build/sign/DMG/install pipeline |
| `Package.swift` | SPM manifest; products + dependencies |

**Find result**: `find . -name "*.entitlements" -not -path '*/.build/*' -not -path '*/.git/*'` returned **zero matches**. There is no committed `.entitlements` file anywhere in the repo. The entitlements plist is constructed inline in `scripts/package.py:399-407` (string literal `ENTITLEMENTS_PLIST`) and written to a tempfile at sign time.

**Bundle composition** (full file list under `Ninimma.app/`):
```
Contents/Info.plist
Contents/PkgInfo
Contents/_CodeSignature/CodeResources
Contents/MacOS/PersonalScribeAppKit
Contents/Resources/Ninimma.icns
```
No `.DS_Store`, no `.git*`, no `*.log`, no debug/dSYM files inside the bundle. Clean.

**Live codesign verification** (via `codesign -dvvv` and `codesign -d --entitlements`):

- Identifier: `com.nitkrar.personal_scribe`
- Format: `app bundle with Mach-O thin (arm64)`
- Hardened runtime: ENABLED (`flags=0x10000(runtime)`)
- Authority: `Nitkrar Dev` (self-signed)
- TeamIdentifier: `not set`
- Entitlements (the only one): `com.apple.security.device.audio-input = true`

---

## 3. Findings

### F1 — No app-sandbox entitlement → unrestricted egress and filesystem access for any 3p dep at runtime
**Severity: HIGH (architectural / supply-chain risk)**
**Where**: `scripts/package.py:399-407` (`ENTITLEMENTS_PLIST` string literal); shipped binary (`codesign -d --entitlements` confirms)
**What**: The shipped bundle's complete entitlement set is `{ com.apple.security.device.audio-input: true }`. No `com.apple.security.app-sandbox`. No `com.apple.security.network.client`. No filesystem-access entitlements (because there's no sandbox to gate them).

Consequence: at the kernel level, the process runs as the user with no containerization. **Any code path inside the binary** — application code, FluidAudio, GRDB, transitively linked C libs (CoreML, Accelerate, etc.), anything injected by a future supply-chain compromise — can:

- Open arbitrary outbound TCP/UDP sockets (`URLSession`, `Network.framework`, BSD sockets) without TCC prompt and without entitlement gate. The `NSMicrophoneUsageDescription` claim "Audio never leaves your device" is enforced **only by source-level discipline**, not by any OS sandbox; a future malicious update or compromised dep could exfiltrate the audio buffer over HTTPS and the OS would not block it.
- Read any file in `$HOME` reachable by the user UID (subject to TCC for "protected" locations like `~/Documents`, `~/Desktop`, `~/Downloads`, iCloud — those still prompt regardless of sandbox state).
- Write to `/tmp`, the install dir, `~/Library/Application Support/personal_scribe/` (already used legitimately) or anywhere else the user can write.
- Spawn subprocesses (`Process`/`posix_spawn`). Hardened runtime doesn't block child processes; it restricts what they can do dynamically.

**Why it matters**: Ninimma's privacy story is "everything happens locally." That story is enforced today by the source code (no `URLSession` calls to remote endpoints in app code) and the user's trust in the FluidAudio + GRDB packages. A sandbox would convert that from a *trust-and-audit* claim into a *kernel-enforced* claim — catastrophic regressions (compromised 3p update, dev mistake, malicious extension) would be blocked rather than discovered post-hoc.

**Mitigation** (in order of intrusiveness):

1. **Add app-sandbox + minimal allowlist**. Tracked entitlements would be:
   - `com.apple.security.app-sandbox = true`
   - `com.apple.security.device.audio-input = true` (already present)
   - `com.apple.security.files.user-selected.read-write = true` (paste-target access if needed)
   - Possibly `com.apple.security.network.client = true` ONLY for FluidAudio's HuggingFace model-download path (see project memory `project_fluidaudio_model_bundling.md` — bundled model loading via `MLModel(contentsOf:)` already avoids network on warm path; cold first-run download would need the entitlement).
   - **Do not** add `com.apple.security.network.client` if model download can be fully replaced by bundled `.mlmodelc` resources at all entry points.
2. **Pre-sandbox stopgap**: assert the *absence* via runtime self-check on launch (read own entitlements, log if `app-sandbox` ever appears so a future packaging mistake doesn't accidentally enable a half-broken jail). Cheap; doesn't gain real security.
3. **Document the trust boundary**: explicit note in user-facing privacy copy that the local-only guarantee depends on dep audits, not kernel sandboxing.

The right move is (1). The DMG today carries the privacy claim "Audio never leaves your device" in the mic prompt string (`Info.plist:48-49`) but ships zero kernel-enforced backing for it. A user reasonably reading that string trusts the OS to enforce it; the OS does not.

---

### F2 — `codesign --deep` is deprecated and masks per-component signing intent
**Severity: LOW (correctness / future-compat)**
**Where**: `scripts/package.py:431` (`"--deep"` argument to `codesign`)
**What**: The signing call passes `--deep`, which recursively re-signs every nested binary/bundle with the same identity + entitlements. Apple has explicitly deprecated `--deep` for distribution signing — recommendation is to sign each nested component (helpers, frameworks, XPC services) explicitly with its own entitlement scope, then sign the outer bundle last. See Apple TN3127.

For *this* app the consequence is benign because the bundle is flat — one Mach-O, no Frameworks/, no XPC, no helpers (verified via `find Ninimma.app -type f` showing only the binary + Info.plist + PkgInfo + icns + CodeResources). `--deep` is a no-op here in practice. But:
- A future addition of a Sparkle-style updater, a CLI helper in `Contents/MacOS/`, or a Frameworks/ directory will silently inherit the app's audio-input entitlement under `--deep`, which is not what you want.
- `codesign --deep` is logged as a warning by the notarytool in some macOS versions; if this app ever moves to notarization the warning will surface.

**Mitigation**: drop `--deep`. The current bundle has nothing nested that needs recursive signing. If/when a helper or framework is added, sign it explicitly first with its own entitlement plist.

---

### F3 — `--timestamp=none` blocks notarization and weakens revocation posture
**Severity: LOW (today, gating for distribution upgrade path)**
**Where**: `scripts/package.py:436` (`"--timestamp=none"`)
**What**: The signing call disables Apple's secure timestamp. Without a timestamp:
- The signature cannot be notarized (notarytool requires a secure timestamp).
- If the signing identity is ever revoked, the signature is invalid even for binaries signed before the revocation date — there's no trusted "this was signed before the revocation" proof.

Today the app is self-signed by a local cert ("Nitkrar Dev"), so notarization isn't possible anyway. But if/when this moves to a Developer ID identity for public distribution, this flag must be removed first or the signed bundle won't notarize.

**Mitigation**: drop `--timestamp=none` (or change to `--timestamp`) at the point distribution moves to a Developer ID identity. Not actionable today; flag for the distribution-upgrade plan.

---

### F4 — Self-signed Developer ID lookalike + ad-hoc fallback path; no notarization
**Severity: INFORMATIONAL (matches stated dev posture; downstream user trust impact)**
**Where**: `scripts/package.py:47-49` (`SIGN_IDENTITY_PREFERRED = "Nitkrar Dev"`); `:367-396` (`resolve_signing_identity`)
**What**: The script prefers a self-signed cert named "Nitkrar Dev" (a Developer-ID-looking name; intentional per script comments) and falls back to ad-hoc `-` if not present. Both paths are explicitly local-only signatures: no Apple-notarized stapling, no Gatekeeper trust at first launch. Comments at top of `package.py:18-19` document the workaround:
> First-run Gatekeeper: right-click Ninimma.app → Open, OR `xattr -dr com.apple.quarantine /Applications/Ninimma.app`

This is a legitimate dev/distribution choice (no Apple Developer Program enrollment), but it has security implications for downstream DMG users: a tampered DMG would not show a signature mismatch the same way a notarized app would, and any DMG-vs-installed-binary divergence isn't surfaced by Gatekeeper's notarization checks. Users who run the `xattr` command also lose Gatekeeper's ongoing checks for malicious modification.

**Mitigation**: documentation-level. If/when the project enrolls in the Apple Developer Program, switch to Developer ID Application + notarytool. Not a current-state finding — recording for transparency in the audit.

---

### F5 — `package.py:241` deletes `~/Library/Preferences/<bundle>.plist*` via glob during `--reset`
**Severity: INFORMATIONAL (dev tooling, not shipped behavior)**
**Where**: `scripts/package.py:240-241`
**What**: During `--reset`, the script enumerates `prefs_dir.glob(f"{BUNDLE_ID}.plist*")` and unlinks each. The glob pattern `com.nitkrar.personal_scribe.plist*` matches:
- `com.nitkrar.personal_scribe.plist` (intended)
- `com.nitkrar.personal_scribe.plist.lockfile` (intended; cfprefsd lock)
- Any future file beginning with that prefix.

Because `Path.glob` here is bound to the explicit `prefs_dir` (`~/Library/Preferences/`) and the prefix is the full bundle ID, there's no realistic path-traversal or spillover risk. Recording for completeness — the glob is bounded and the action is dev-machine-local. No mitigation needed.

---

### F6 — Bundle ships clean; no debug files / VCS metadata / logs leaking into DMG
**Severity: NONE (positive finding)**
**Where**: `find Ninimma.app -type f` returned exactly 5 files; none of `.DS_Store`, `.git*`, `*.log`, `*.dSYM` present. DMG composition (`scripts/package.py:455-475`) uses `shutil.copytree(APP_PATH, staging/Ninimma.app)` which copies only the assembled bundle, not the surrounding repo. Symlink to `/Applications` is the standard drag-install affordance. `hdiutil create -format UDZO -fs HFS+` is correct for read-only compressed DMG.

The `assemble_app` function (`:327-361`) builds the bundle from scratch in a wiped directory each run (`shutil.rmtree(APP_PATH)` before `mkdir`), so stale artifacts from prior builds cannot leak in.

The `strip -x` invocation on release builds (`:342-344`) is correct per the project memory note `project_app_size_strip.md`. Stripping removes symbol tables but does not affect signing (signing happens after strip in `main()` order at `:515-517`).

---

### F7 — Single legitimate usage description; no overreach in Info.plist
**Severity: NONE (positive finding)**
**Where**: `Ninimma.app/Contents/Info.plist:48-49` (`NSMicrophoneUsageDescription`)
**What**: The only usage description is for microphone access (the audio-input entitlement is matched by the runtime TCC prompt string). Notably **not present**:
- `NSAppTransportSecurity` — no ATS configuration at all (default ATS applies; no allow-arbitrary-loads, no exception domains). FluidAudio model downloads over HTTPS pass default ATS; this is acceptable.
- `CFBundleURLTypes` — no URL scheme registration. App cannot be invoked via custom URL.
- `NSAppleEventsUsageDescription` — no AppleEvents prompt. Note: project memory `project_macos_system_audio_mute.md` says system-audio mute uses `NSAppleScript` (`set volume output muted`); this *should* trigger an Automation TCC prompt at runtime when first invoked. Confirm whether `NSAppleEventsUsageDescription` needs to be added — without it the prompt may surface the bundle name without an explanation string. **Cross-reference for Lane 4 (runtime permissions) or Lane 5 (FluidAudio): does the AppleScript mute path silently fail on a fresh user without a usage string?** Out of scope here, flagging.
- `LSUIElement` — explicitly absent (Dock-visible launch). The Info.plist comment block at `:33-39` documents that "Background mode" toggles activation policy at runtime via `NSApp.setActivationPolicy(.accessory)` rather than via Info.plist. The pref vs bundle alignment caveat from memory `feedback_bundle_pref_alignment.md` applies — flagged as a soft cross-reference, not a finding for this lane.

---

## 4. Coverage gaps

**Within scope, things I did NOT verify**:

1. **What entitlements the *executable inside the DMG* actually carries vs what the script claims.** I verified the committed `Ninimma.app` (last built 2026-04-24 per its mtime). The script could in principle drift from the committed bundle. To close: a Lane-6.b lane should diff the entitlements of a freshly-built `Ninimma.dmg` (Codex review pre-PR) against `ENTITLEMENTS_PLIST` source-of-truth in `package.py`.
2. **Inside-binary string scan for unexpected URLs / hardcoded API endpoints.** The trust-posture lane is "what does the OS allow" — it deliberately does not enumerate "what does the binary try to do." Code-level egress audit (FluidAudio model download URLs, telemetry endpoints if any, GRDB SQLite-cipher remote keys) is Lane 5 territory, not Lane 6.
3. **DMG signature.** I did not verify whether the `.dmg` itself is signed (separate from the `.app` inside). `hdiutil create` without an explicit `-sign` flag produces an unsigned DMG. The script does not sign the DMG. For self-signed distribution this is consistent; for Developer-ID this would need to be added (`codesign --sign <id> Ninimma-0.1.0.dmg`).
4. **AppleScript path TCC prompts (cross-lane).** As noted in F7, Lane 6 cannot determine whether `NSAppleScript` mute triggers a TCC prompt without `NSAppleEventsUsageDescription`. Cross-reference Lane 4 / runtime audit.
5. **Static-link list.** I did not run `otool -L` on the binary to enumerate the actual linked dynamic libraries. Statically-linked deps (FluidAudio/GRDB if static) won't appear; dylib deps would. Bundle-trust posture is the same regardless, so this is informational only.
6. **Hardened-runtime sub-flags.** I confirmed `--options runtime` is asserted but did not enumerate which sub-entitlements are NOT used (`com.apple.security.cs.disable-library-validation`, `com.apple.security.cs.allow-jit`, etc.). The default hardened-runtime posture (none of those asserted) is the strongest setting; the script does not relax any of them. Recording this as positive coverage rather than a gap.
7. **`Package.resolved` integrity / supply-chain pinning.** I did read `Package.swift` (FluidAudio `exact: 0.13.6`, GRDB `exact: 7.10.0` — both pinned to exact versions, good). I did not inspect `Package.resolved` for hash pinning. Lane 5 (3p deps) territory.

**Out of scope for Lane 6 by design**:
- Source-level network-call audit (Lane 5).
- Runtime permission flow / TCC prompt UX (Lane 4).
- Binary disassembly for hidden URLs/endpoints (Lane 5).
- Keychain access or credential storage (separate lane if applicable).

---

## Summary

The shipped Ninimma.app has **hardened runtime enabled, a single legitimate entitlement (mic), no ATS exceptions, no URL handlers, a clean bundle composition, and no sandbox**. The dominant finding is **F1**: the absence of the app-sandbox entitlement means any embedded 3p dep (FluidAudio, GRDB, transitive C libs) has unrestricted network egress and unrestricted user-readable filesystem access at the kernel level. The "Audio never leaves your device" claim in the mic prompt is enforced today only by source-level discipline + dep audits — not by the OS. Adopting the sandbox + a minimal entitlement allowlist would convert that promise from trust-based to kernel-enforced. F2 / F3 are minor signing-pipeline cleanups gating future notarization. F4 is informational about the self-signed dev-distribution posture. F5 / F6 / F7 are positive / informational findings.
