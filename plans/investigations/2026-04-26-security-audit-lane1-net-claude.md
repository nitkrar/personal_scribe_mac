# Security Audit — Lane 1: Network egress (Claude)

Date: 2026-04-26
Scope: `/Sources/` only (production code)
Reviewer: Claude (independent of Codex peer review)

## 1. Threat-model framing

Ninimma processes microphone audio and the resulting transcripts entirely on-device — both classes of data are sensitive. Beyond raw recordings/transcripts, file-system paths (the user's `~/Library/Application Support/personal_scribe/` tree and any user-chosen base directory), the user's macOS short name (encoded in those paths), and any AppleScript/CGEvent state could disclose user identity if exfiltrated. The threat model accepts exactly one outbound channel: HuggingFace model-binary fetches initiated by the FluidAudio dependency to populate the on-disk model cache. Anything else — telemetry beacons, crash uploads, license checks, opaque "phone home" calls, user-content rides on the model-fetch path — would be a finding. Third-party deps (FluidAudio, GRDB, future LLM stacks) are inside the trust boundary for behavior we control via their public APIs but outside the boundary for any code paths inside the dep that we don't invoke. This audit covers only first-party code in `/Sources/`; the dep code itself is a coverage gap (see §4).

## 2. Files audited

Searched the entire `/Sources/` tree (223 Swift files) with the patterns enumerated in the lane brief plus follow-on terms: `URLSession`, `URLRequest`, `URL\(string:`, `NWConnection`, `NWBrowser`, `Network\.`, `dataTask`, `downloadTask`, `uploadTask`, `http://`, `https://`, `socket`, `connect\(`, `getaddrinfo`, `NSURLSession`, `CFNetwork`, `CFSocket`, `BSDSocket`, `WKWebView`, `WebKit`, `import Network`, `import CFNetwork`, `loadHTMLString`, `loadRequest`, `NSURLConnection`, `FluidAudio`, `huggingface`, `download(`, `upload(`, `webhook`, `telemetry`, `analytics`, `crashlytics`, `sentry`, `firebase`, `resolveURL`, `AsrModels`, `loadModel(`, `VadManager(modelDirectory`.

Files read in full or in relevant slice:

- `/Users/nitinkum/Projects/nitkrar/personal_scribe/Sources/PersonalScribeCore/Models/Selection/ModelDescriptor.swift`
- `/Users/nitinkum/Projects/nitkrar/personal_scribe/Sources/PersonalScribeCore/AppBrand/AppBrand.swift`
- `/Users/nitinkum/Projects/nitkrar/personal_scribe/Sources/PersonalScribeAppKit/UnifiedWindow/Tabs/AboutSubTab.swift`
- `/Users/nitinkum/Projects/nitkrar/personal_scribe/Sources/PersonalScribeAppKit/Settings/AIModelsTab.swift` (URL/network grep — none found)
- `/Users/nitinkum/Projects/nitkrar/personal_scribe/Sources/PersonalScribeAppKit/Settings/GeneralTab.swift` (lines 120–160)
- `/Users/nitinkum/Projects/nitkrar/personal_scribe/Sources/PersonalScribeAppKit/Settings/AdvancedTab.swift`
- `/Users/nitinkum/Projects/nitkrar/personal_scribe/Sources/PersonalScribeAppKit/Overlay/PillOverlayController.swift` (lines 435–470)
- `/Users/nitinkum/Projects/nitkrar/personal_scribe/Sources/PersonalScribeAppKit/MenuBar/StatusItemController.swift` (lines 425–445)
- `/Users/nitinkum/Projects/nitkrar/personal_scribe/Sources/PersonalScribeSession/Models/Selection/ActiveModelService.swift`
- `/Users/nitinkum/Projects/nitkrar/personal_scribe/Sources/PersonalScribeSession/Models/Selection/ModelBoundProcessorProvider.swift`
- `/Users/nitinkum/Projects/nitkrar/personal_scribe/Sources/PersonalScribeSession/Models/Selection/ModelBoundTranscriberProvider.swift`
- `/Users/nitinkum/Projects/nitkrar/personal_scribe/Sources/PersonalScribeTranscription/FluidAudioInferenceClient.swift`
- `/Users/nitinkum/Projects/nitkrar/personal_scribe/Sources/PersonalScribeTranscription/Models/Selection/ModelAwareFluidAudioInferenceClient.swift`
- `/Users/nitinkum/Projects/nitkrar/personal_scribe/Sources/PersonalScribeTranscription/Models/Selection/ModelAwareFluidAudioTranscriber.swift`
- `/Users/nitinkum/Projects/nitkrar/personal_scribe/Sources/PersonalScribeTranscription/Adapters/FluidAudioParakeetTranscriberAdapter.swift`
- `/Users/nitinkum/Projects/nitkrar/personal_scribe/Sources/PersonalScribeTranscription/Adapters/FluidAudioStreamingTranscriberAdapter.swift`
- `/Users/nitinkum/Projects/nitkrar/personal_scribe/Sources/PersonalScribeTranscription/Adapters/FluidAudioQwenTranscriberAdapter.swift`
- `/Users/nitinkum/Projects/nitkrar/personal_scribe/Sources/PersonalScribeTranscription/Adapters/FluidAudioOfflineDiarizerAdapter.swift`
- `/Users/nitinkum/Projects/nitkrar/personal_scribe/Sources/PersonalScribeVAD/FluidAudioVadProvider.swift`
- `/Users/nitinkum/Projects/nitkrar/personal_scribe/Package.swift`

Cross-checked tests directory for hostnames pointing into production paths — only RFC-2606 reserved `example.invalid` sentinels found in fakes (e.g. `Tests/PersonalScribeCoreTests/AppStore/Fakes/FakePermissionService.swift:44`), which never resolve.

## 3. Findings

The `/Sources/` tree contains exactly five spots where a URL or http literal appears, plus four FluidAudio-manager call sites that delegate downloading to the dep. Each is reviewed below.

### Inventory of every URL/http literal in `/Sources/`

| File:line | Literal | Reachable in production? | Carries user data? |
|---|---|---|---|
| `PersonalScribeCore/Models/Selection/ModelDescriptor.swift:195` | `"https://huggingface.co/\(repository)/resolve/\(revision)/\(relativePath)"` | **No** — defined-but-unused | n/a |
| `PersonalScribeAppKit/UnifiedWindow/Tabs/AboutSubTab.swift:84` | `"https://mythlok.com/ninimma/"` | Yes, on user tap | No (handed to OS via `Link`) |
| `PersonalScribeAppKit/Overlay/PillOverlayController.swift:465` | `"about:blank"` | No — fallback in unused legacy path | n/a |
| `PersonalScribeAppKit/Settings/GeneralTab.swift:136` | `"x-apple.systempreferences:com.apple.LoginItems-Settings.extension"` | Yes, on user tap | No (system URI scheme) |
| `PersonalScribeAppKit/MenuBar/StatusItemController.swift:434, 441` | `"x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"` and `…?Privacy_ListenEvent` | Yes, on user tap | No (system URI scheme) |

Plus several `FakePermissionService` test-only `https://example.invalid/...` hosts referenced as the `systemSettingsDeepLink` return value in tests — never opened, RFC-2606 reserved name. (Outside `/Sources/`.)

No `URLSession`, `URLRequest`, `NSURLConnection`, `WKWebView`, `Network` framework, `CFNetwork`, `CFSocket`, BSD socket, `getaddrinfo`, or `NWConnection`/`NWBrowser` calls anywhere in `/Sources/`. No `import Network`, `import CFNetwork`, or `import WebKit`. No analytics/telemetry/crashlytics/sentry/firebase identifiers. The first-party code surface for direct network egress is therefore zero — every byte that leaves the box does so through FluidAudio (model fetch) or `NSWorkspace.shared.open` (URL handed to the OS).

### Finding 1 — LOW: `ModelDescriptor.resolveURL(for:)` is dead code

- **Severity:** low
- **Where:** `/Users/nitinkum/Projects/nitkrar/personal_scribe/Sources/PersonalScribeCore/Models/Selection/ModelDescriptor.swift:193-197`
- **What's there:**

  ```swift
  public func resolveURL(for relativePath: String) -> URL {
      URL(
          string: "https://huggingface.co/\(repository)/resolve/\(revision)/\(relativePath)"
      )!
  }
  ```

- **Reachability:** Confirmed zero production callers. `grep -rn "resolveURL" Sources Tests` returns only the definition itself (worktree copies in `.claude/worktrees/` are excluded; they're agent scratch checkouts, not production). No call sites in `Tests/` either, so it's not even exercised by unit tests.
- **Why it's a concern:** The literal builds a HuggingFace `resolve/<sha>/<path>` URL by concatenating `repository`, `revision`, and `relativePath`. Today none of those three fields carries user content — they're hard-coded in `BuiltInModelCatalog`. But a future developer who calls `descriptor.resolveURL(for:)` and feeds it a user-derived `relativePath` (e.g. a custom-vocabulary file path or anything PII-shaped) would create a path-injection vector that smuggles user data into the URL path. Today's actual download path — `AsrModels.load(from: directory, …)` — does not use this method; it drives FluidAudio's internal HuggingFace fetcher with a local directory URL only. So the method is purely a latent attractor.
- **Mitigation suggestions (in order of preference):**
  1. Delete the method. The actual download path inside FluidAudio doesn't need it; it's only a temptation for a future caller to write a wrong-layer fetch.
  2. If keeping it for symmetry / introspection, add `internal` access and a doc comment stating that `relativePath` MUST come from `descriptor.requiredRelativePaths` (which is hard-coded in the catalog) and is never user-derived. Add a debug-build assertion `assert(requiredRelativePaths.contains(relativePath))` to make a misuse blow up loudly.
  3. (Less preferred) Add a Forbidden-Duplicates rule + lint guard so any future call-site outside the catalog test fixtures fails CI.

### Finding 2 — INFORMATIONAL: AboutSubTab `mythlok.com` link opens via OS, not in-app

- **Severity:** none / informational
- **Where:** `/Users/nitinkum/Projects/nitkrar/personal_scribe/Sources/PersonalScribeAppKit/UnifiedWindow/Tabs/AboutSubTab.swift:84`
- **What's there:** `Link(destination: URL(string: "https://mythlok.com/ninimma/")!) { … }` inside `AboutSubTab` (which is reachable from production at `UnifiedWindowView.swift:220`).
- **Reachability:** Yes — the user must tap it.
- **Why it's not a concern:** SwiftUI `Link` lowers to `NSWorkspace.shared.open(url)` on macOS, which spawns the user's default browser. There is no `WKWebView`, no `URLSession.dataTask`, no in-app HTTP client. The body of the GET is whatever the user's browser sends; Ninimma neither composes nor sees any request body, headers, or query string. No user data is composed into the URL — the path is a constant. There is also no `Referer` rideable from Ninimma since the request originates in Safari.
- **Mitigation:** None required. (Optional polish: if the brand later wants tighter privacy posture, flip to `mailto:` or strip the link — but as-is this is a safe outbound user-initiated browser navigation.)

### Finding 3 — INFORMATIONAL: `about:blank` fallback in legacy pill-overlay path is unreachable

- **Severity:** none / informational
- **Where:** `/Users/nitinkum/Projects/nitkrar/personal_scribe/Sources/PersonalScribeAppKit/Overlay/PillOverlayController.swift:464-466` — `LegacyPillOverlayPermissionService.systemSettingsDeepLink` returns `URL(string: "about:blank")!`.
- **Why it's not a concern:** The legacy provider is only used as a stub when no real `PermissionService` is wired (no production composition uses this path — `PersonalScribeAppMain.swift` always wires the real `PermissionServiceAdapter`). Even if invoked, `LegacyPillOverlayPermissionService.request()` returns `openedSettings: false`, so the `about:blank` URL is never handed to `NSWorkspace.shared.open`. It's a typed-protocol-satisfying placeholder. No data egress vector.
- **Mitigation:** None required. (Optional: replace with `fatalError("LegacyPillOverlayPermissionService should never be used in production")` to make accidental wiring loud — but that's a robustness, not a security, suggestion.)

### Finding 4 — INFORMATIONAL: System-Settings deep links are local URI schemes

- **Severity:** none / informational
- **Where:**
  - `Sources/PersonalScribeAppKit/Settings/GeneralTab.swift:136` — `x-apple.systempreferences:com.apple.LoginItems-Settings.extension`
  - `Sources/PersonalScribeAppKit/MenuBar/StatusItemController.swift:434` — `…?Privacy_Microphone`
  - `Sources/PersonalScribeAppKit/MenuBar/StatusItemController.swift:441` — `…?Privacy_ListenEvent`
- **What's there:** All three are user-tap-driven `NSWorkspace.shared.open(url)` calls with constant `x-apple.systempreferences:` URIs.
- **Why it's not a concern:** The `x-apple.systempreferences:` scheme is handled locally by the System Settings app on the same machine. No network round-trip; no body; no query parameters carry user state (the `?Privacy_Microphone` / `?Privacy_ListenEvent` query strings are pane-selectors hard-coded in source). Mentioned only because the lane brief asked.
- **Mitigation:** None required.

### Finding 5 — INFORMATIONAL: FluidAudio model-fetch surface

- **Severity:** none / informational (assumes FluidAudio is trusted per threat model)
- **Where:** Five call sites delegate to FluidAudio managers:
  - `Sources/PersonalScribeTranscription/FluidAudioInferenceClient.swift:43` — `AsrModels.load(from: directory, version:, progressHandler:)`
  - `Sources/PersonalScribeTranscription/Models/Selection/ModelAwareFluidAudioInferenceClient.swift:39` — same `AsrModels.load`
  - `Sources/PersonalScribeTranscription/Adapters/FluidAudioParakeetTranscriberAdapter.swift:299` — same `AsrModels.load` (live manager)
  - `Sources/PersonalScribeTranscription/Adapters/FluidAudioStreamingTranscriberAdapter.swift:53` — `StreamingEouAsrManager.loadModels(modelDir:)`
  - `Sources/PersonalScribeTranscription/Adapters/FluidAudioQwenTranscriberAdapter.swift:149` — `Qwen3AsrManager.loadModels(from:)`
  - `Sources/PersonalScribeTranscription/Adapters/FluidAudioOfflineDiarizerAdapter.swift:208` — `OfflineDiarizerManager.prepareModels(directory:)`
  - `Sources/PersonalScribeVAD/FluidAudioVadProvider.swift:97` — `VadManager(config:vadModel:)` (deliberately the bundled-model overload, NOT `VadManager(modelDirectory:)` — the file's own doc-comment at lines 11-15 calls out that the latter would silently re-download from HuggingFace)
- **What we pass into FluidAudio:**
  - A local-filesystem `URL` (`storageLocator.url(for: .models).appendingPathComponent(descriptor.repoFolderName)`).
  - A model-version enum (`AsrModelVersion.v2 / .v3 / .tdtCtc110m` or equivalents).
  - A progress-callback closure that receives `DownloadUtils.DownloadProgress` and republishes mapped phase/fraction. **The closure does not echo any user-content; the broadcaster only forwards `phase`/`fractionCompleted` (and `receivedBytes`/`expectedBytes` set to `0`/`nil`).**
- **What we do NOT pass:** No microphone samples, no transcript text, no PCM buffers, no user identifiers, no file paths beyond the canonical models directory, no headers, no tokens. The only identifiers in flight are the hard-coded HuggingFace repo + revision triples baked into `BuiltInModelCatalog` (see `ModelDescriptor.repository` / `.revision`).
- **VAD safe-bundle invariant:** `FluidAudioVadProvider.swift:88-97` loads the bundled `silero-vad.mlmodelc` directly with `MLModel(contentsOf:configuration:)` and constructs `VadManager(config:vadModel:)`. The doc comment at lines 11-15 explicitly calls out that `VadManager(modelDirectory:)` is a HuggingFace-fetch trap and is forbidden. This invariant is correctly held; finding for the record.
- **Diarizer note:** `FluidAudioOfflineDiarizerAdapter.swift:139` passes `storageLocator.url(for: .models).standardizedFileURL` (the models root directory, not a subfolder) into `OfflineDiarizerManager.prepareModels(directory:)`. Per the inline comment, the manager appends FluidAudio's diarizer repo folder name internally. If that diarizer model isn't yet in `requiredRelativePaths` and FluidAudio walks the parent directory enumerating siblings, it won't leak data outbound — `prepareModels` is a fetch-on-miss API, not an upload. No concern, but flagged so a Codex reviewer cross-checking can spot-check the dep.
- **Mitigation:** Pin and audit the FluidAudio version (Package.swift line 42 references `https://github.com/FluidInference/FluidAudio.git`). Out of scope for this lane (Lane 1 is first-party; dep audit is its own scope).

### Confirmation against lane-brief checklist

- **`ModelDescriptor.resolveURL` defined-but-unused?** Yes — confirmed zero callers in `/Sources/` and `/Tests/`. Filed as Finding 1 (LOW).
- **`AboutSubTab` `https://mythlok.com/ninimma/` link — in-app or via NSWorkspace?** Via `Link` → SwiftUI lowers to `NSWorkspace.shared.open`. Spawns Safari. No in-app web view. Filed as Finding 2 (informational).
- **AIModelsTab download UI wiring:** Reviewed — no URL or network call inside the tab. Tab calls `service.download(descriptor)` (line 84), which routes to `ActiveModelService.download(_:)`, which calls `downloadHandler` → `ModelBoundTranscriberProvider.download` (or `ModelBoundProcessorProvider.download` for the new adapters) → eventually `AsrModels.load(from:)` inside FluidAudio. No URL string is constructed by first-party code; `descriptor.repository` / `.revision` are passed via `AsrModelVersion` enum, not as raw strings.
- **Every `download(progress:)` callsite (ActiveModelService, ModelBoundProcessorProvider, ModelBoundTranscriberProvider):** Reviewed. All three centralize on `inference.loadModel(from: directory, runtimeVariant:, progressHandler:)` for the live path or stub-write to disk for the #078 placeholder adapters in `ModelBoundProcessorProvider.swift` (`ProcessorProviderStubAdapterSupport.materializeArtifacts`, lines 209-234). The stub path writes fake `.mlmodelc` / `.json` placeholder bytes locally — no network involvement.

**Confirmed:** Only HuggingFace-hosted model URLs are reachable from first-party `/Sources/` code, and only via FluidAudio's internal fetcher. The first-party code passes only a local directory URL + a model-version enum + a progress callback. No first-party code path can ride user content (recordings, transcripts, file paths beyond the models directory, identifiers) into a request body, header, or query string.

## 4. Coverage gaps

- **FluidAudio source code itself.** This audit treats FluidAudio as opaque past its public manager APIs. We trust:
  - `AsrModels.load(from:version:progressHandler:)` only contacts HuggingFace and writes to the supplied directory.
  - `StreamingEouAsrManager.loadModels(modelDir:)`, `Qwen3AsrManager.loadModels(from:)`, `OfflineDiarizerManager.prepareModels(directory:)`, `VadManager(config:vadModel:)` follow the same shape.
  - The `progressHandler` closure receives only `DownloadUtils.DownloadProgress` (phase + fractionCompleted) and is not a back-channel for the dep to stuff arbitrary data through. If FluidAudio extended `DownloadProgress` to carry user-derived fields, our re-broadcast in `ActiveModelService.ingest(progress:)` (lines 333-355) would forward only `phase` / `fractionCompleted` and discard everything else by mapping shape — but the dep would still have seen any data it logged.
  - The dep does not contain telemetry / crash-upload / "phone home" code that we don't see at our integration boundary.
  
  Out-of-scope for this lane; suggest a separate FluidAudio source-audit lane (or pinning a known-good revision and diffing against it on bumps).

- **GRDB.** Not searched in this lane. GRDB.swift is a SQLite wrapper and historically has no network surface, but we did not verify in-tree.

- **Compiled binary blobs.** `Sources/PersonalScribeVAD/Resources/silero-vad.mlmodelc/` and any other shipped `.mlmodelc` / model artifacts are not audited — a malicious binary could contain code, but `MLModel(contentsOf:)` runs them inside CoreML's sandboxed evaluator; a compromised model can produce wrong outputs but cannot directly initiate egress from the model itself. Out of scope for static source audit.

- **Build-tool / CI plugins.** Not audited (`scripts/`, `.github/`, packaging glue). A `swift package plugin` could in principle phone home at build time; out of lane scope.

- **System frameworks called via Foundation/AppKit.** `NSWorkspace.shared.open(url)`, `MLModel(contentsOf:)`, `AVAudioEngine`, `NSAppleScript` (system-mute path), and `CGEventPost` all run inside Apple's process model and were not exhaustively traced for indirect networking. No specific suspicion — flagging the boundary.

- **Dynamic loaders / `dlopen`.** Searched implicitly via the keyword set (none found). No first-party `dlopen`/`Bundle.load`/`@_silgen_name` patterns observed.

- **`Tests/` tree.** Lane scope is `/Sources/`. Tests were spot-checked for hostname patterns and only `https://example.invalid/...` (RFC-2606 reserved) sentinels surfaced — not a production concern. A future lane could harden test fakes to reject any URL with a non-`.invalid` / non-`localhost` host as a regression guard.

- **Info.plist / ATS.** No `NSAppTransportSecurity` overrides found in `Ninimma.app/Contents/Info.plist`. ATS defaults apply (TLS-only, no arbitrary loads). The bundled Info.plist is the build artifact, not the source; if Ninimma later ships a per-target `Info.plist` declaring `NSAllowsArbitraryLoads` or per-domain exceptions, that should be reviewed in a Lane-1 follow-up.
