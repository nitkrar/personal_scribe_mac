# 2026-04-26 Security Audit — Lane 1 Network egress (Codex retry)
## 1. Threat-model framing
I audited first-party `Sources/` plus the production-reachable `FluidAudio` download path behind `AIModelsTab`, startup prewarm, and session `prepare()` calls. The live app path does not send transcript text, clipboard contents, audio samples, or other user-derived content in any URL query, request body, or header that I could trace. `AboutSubTab`’s `https://mythlok.com/ninimma/` is a browser handoff via `Link`, not an in-process fetch; `x-apple.systempreferences:` and `about:blank` hits are non-network. The two caveats are that `FluidAudio` allows its registry host/proxy to be redirected by environment variables, and the live downloader fetches HuggingFace tree/vocabulary metadata in addition to model binaries.
## 2. Files audited
- `Sources/PersonalScribeCore/Models/Selection/ModelDescriptor.swift`
- `Sources/PersonalScribeAppKit/UnifiedWindow/Tabs/AboutSubTab.swift`
- `Sources/PersonalScribeAppKit/Settings/AIModelsTab.swift`
- `Sources/PersonalScribeSession/Models/Selection/ActiveModelService.swift`
- `Sources/PersonalScribeSession/Models/Selection/ModelBoundTranscriberProvider.swift`
- `Sources/PersonalScribeTranscription/Models/Selection/ModelAwareFluidAudioTranscriber.swift`
- `Sources/PersonalScribeTranscription/Models/Selection/ModelAwareFluidAudioInferenceClient.swift`
- `Sources/PersonalScribeTranscription/Models/Selection/FluidAudioRuntimeVariant.swift`
- `Sources/PersonalScribeAppKit/Composition/AppComposition.swift`
- `Sources/PersonalScribeAppKit/Composition/AppStartupCoordinator.swift`
- `Sources/PersonalScribeSession/SessionCoordinator.swift`
- `Sources/PersonalScribeCore/Models/Selection/BuiltInModelCatalog.swift`
- `Package.swift`
- `.build/checkouts/FluidAudio/Sources/FluidAudio/ModelRegistry.swift`
- `.build/checkouts/FluidAudio/Sources/FluidAudio/DownloadUtils.swift`
- `.build/checkouts/FluidAudio/Sources/FluidAudio/ModelNames.swift`
- `.build/checkouts/FluidAudio/Sources/FluidAudio/ASR/Parakeet/AsrModels.swift`
- `Tests/PersonalScribeSessionTests/Models/Selection/ModelBoundTranscriberProviderTests.swift`
- `Tests/PersonalScribeSessionTests/Models/Selection/ModelBoundProcessorProviderTests.swift`
## 3. Findings
- severity: low; file: `.build/checkouts/FluidAudio/Sources/FluidAudio/ModelRegistry.swift:32-38,89-99,103-121`; what: the production-reachable downloader is not hard-pinned to `huggingface.co` because `FluidAudio` honors `REGISTRY_URL` / `MODEL_REGISTRY_URL` and `http_proxy` / `https_proxy`; why: the statement "only HuggingFace-hosted URLs are reachable from first-party code" is not strictly true if the app process is launched with those environment variables, even though the traced requests still carry no user-derived content; mitigation: in shipped builds, ignore those env overrides or assert `ModelRegistry.baseURL == "https://huggingface.co"` before any download begins.
- severity: info; file: `.build/checkouts/FluidAudio/Sources/FluidAudio/DownloadUtils.swift:295-312,396-424,529-540,579-584` and `.build/checkouts/FluidAudio/Sources/FluidAudio/ASR/Parakeet/AsrModels.swift:194-225`; what: the live ASR path performs GETs to HuggingFace tree-listing APIs and downloads JSON metadata such as `parakeet_vocab.json` in addition to model bundle contents; why: "only model binaries fetched" is false as written, although the requests are still queryless/bodyless GETs and I did not find any path for user content to ride them; mitigation: update the allowlist/threat-model wording to include HuggingFace API listing and metadata fetches, or replace recursive tree listing with an explicit baked file manifest if you want binary-only transport.
- severity: info; file: `Sources/PersonalScribeCore/Models/Selection/ModelDescriptor.swift:193-197`; what: `ModelDescriptor.resolveURL(for:)` is dead code with no callers under `Sources/` or `Tests/`; the live downloader does not use `descriptor.repository` or `descriptor.revision`, and instead routes through `FluidAudioRuntimeVariant -> Repo -> DownloadUtils`; why: this is not a current exfil path, but it is an attractive future footgun because it would splice its argument directly into a URL path if someone starts calling it with user-derived input; mitigation: delete it, reduce its visibility, or document/sanitize it aggressively before any future use.
## 4. Coverage gaps
I did not run the app, capture traffic, or inspect the real launch environment, so this is a static read-only audit only. I did not exhaustively review every non-FluidAudio dependency because `Package.swift` only exposes `FluidAudio` and `GRDB`, and the traced network surface was entirely in `FluidAudio`. The mandated one-line grep misses multi-line `URL(string:)` constructions; I manually spot-checked additional deeplink call sites and they resolved to browser or System Settings handoffs, not in-app HTTP.
