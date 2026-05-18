# #098 phase 1 — paper spike: whisper.cpp Swift binding + CoreML/ANE feasibility audit

Scope: source audit only. No `personal_scribe` code changes and no local runtime benchmarks were run.

## 1. Swift binding comparison

| Candidate | Activity snapshot (2026-05-18) | Public API fit for a transcriber | CoreML exposure | Model-file expectations | Verdict |
| --- | --- | --- | --- | --- | --- |
| `whisper.spm` | Last commit `2024-05-27`, `5` open issues, `0` PRs updated in last 6 months. Upstream README says it will soon be archived and redirects users to `whisper.cpp`. [spm-commit] [spm-repo] [spm-prs] [spm-readme] | Exposes the C target `whisper`, so it is usable, but there is no higher-level Swift wrapper. [spm-package] | Hard-defines `WHISPER_USE_COREML` and `WHISPER_COREML_ALLOW_FALLBACK`, but also excludes `ggml-metal` with an inline TODO saying Metal does not build. [spm-package] | Same upstream `ggml-*.bin` plus optional sibling `*-encoder.mlmodelc`; no alternate format. [spm-package] | `No`. Sunset package, stale, and Apple fallback path is weaker because Metal is excluded. |
| `SwiftWhisper` | Latest default-branch commit `2023-08-17`, `12` open issues, `0` PRs updated in last 6 months. Open issue `#46` explicitly calls out that it has not been updated in over 2 years. [swiftwhisper-commit] [swiftwhisper-repo] [swiftwhisper-prs] [swiftwhisper-issue-46] | Best convenience API of the three: `Whisper(fromFileURL:)`, `transcribe(audioFrames:) async`, delegate callbacks, and cleanup in `deinit`. Good enough for the current batch-style Transcriber protocol. [swiftwhisper-readme-usage] [swiftwhisper-whisper] | Hard-defines `WHISPER_USE_COREML` and `WHISPER_COREML_ALLOW_FALLBACK` on Apple platforms. README requires a sibling `-encoder.mlmodelc` and the `fromFileURL` initializer for CoreML. [swiftwhisper-package] [swiftwhisper-readme-coreml] | Same upstream `ggml-*.bin` plus sibling `*-encoder.mlmodelc`. [swiftwhisper-readme-coreml] | `No`. The wrapper is nice, but repo activity is stale and open issue `#37` shows `large-v3` crashes; `#46` reports turbo/q8 model failures on the old vendored `whisper.cpp`. [swiftwhisper-issue-37] [swiftwhisper-issue-46] |
| Direct C bridge (`whisper.h`) | Backed by active upstream `ggml-org/whisper.cpp`: latest commit `2026-05-18`, `1196` open issues, `215` PRs updated in last 6 months. [whispercpp-commit] [whispercpp-repo] [whispercpp-prs] | Full control: context params (`use_gpu`, `flash_attn`), one-shot `whisper_full`, lower-level encode/decode entry points, callbacks for segments/progress/cancel, and segment accessors. Upstream ships a Swift example that wraps the raw pointer in an `actor`. [whisper-h-basic] [whisper-h-context] [whisper-h-callbacks] [libwhisper] | The bridge itself does not enable CoreML; the library build does. Upstream’s supported Swift consumption path is the prebuilt XCFramework, and that build turns CoreML on with fallback. [whispercpp-xcframework] [whispercpp-build-xcframework] | Same upstream `ggml-*.bin` plus optional sibling `*-encoder.mlmodelc`. [src-whisper-coreml-path] | `Yes`. Best control surface, least lock-in, and the only path that stays aligned with actively maintained upstream. |

Recommendation: use a thin local Swift wrapper over upstream `whisper.h`, but consume `whisper.cpp` through the upstream XCFramework route rather than `whisper.spm`. `whisper.spm` is effectively sunset, and `SwiftWhisper` is too stale to trust for `large-v3` / `large-v3-turbo`. [spm-readme] [whispercpp-xcframework] [swiftwhisper-issue-37] [swiftwhisper-issue-46]

## 2. CoreML / ANE feasibility

Upstream documentation is clear about what the feature is supposed to be:

- `whisper.cpp` says the **encoder** can run on ANE via Core ML and claims **“more than x3 faster compared with CPU-only execution”**. [whispercpp-readme-coreml]
- The build flag is explicit and **off by default** in CMake: `WHISPER_COREML`. [whispercpp-cmake]
- The conversion script is also explicit that this is **encoder-only** today; the decoder step is still `TODO`. [whispercpp-generate]

For the recommended binding choice, CoreML is only available if the library build includes it. The upstream XCFramework does: it links `CoreML` and passes `-DWHISPER_COREML="ON"` plus `-DWHISPER_COREML_ALLOW_FALLBACK="ON"` in the Apple builds. That means the direct C bridge can expose CoreML cleanly if we consume upstream’s packaged build, and missing/broken CoreML artifacts do not have to be fatal. [whispercpp-build-xcframework]

The field evidence is much weaker than the marketing line:

- `#1616`: one user reports **36s with CoreML vs 13s without** for a short sentence; a follow-up comment reports **220s with CoreML vs 140s without** for the same 6-minute file on M1. [issue-1616] [issue-1616-comment]
- `#2057`: on `ggml-medium.bin`, the reporter shows **encode time 6931 ms with CoreML vs 5827 ms without**, and total runtime **75.7s vs 73.1s**. The maintainer reply is effectively “it depends on your hardware; CoreML might or might not be faster.” [issue-2057] [issue-2057-comment]
- `#2126`: the “first run may take a while” cost appears on **every run**, with three consecutive totals all around `25s`. [issue-2126]
- `#2042` and `#2112`: large-v3 CoreML generation failures remain common enough to show up as user issues. [issue-2042] [issue-2112]
- `#2456`: `large-v3-turbo` on iPhone XR produced incorrect text, and the thread notes that a CoreML encoder above `1GB` may fail to load. [issue-2456] [issue-2456-comments]
- `#3632`: the current `generate-coreml-model.sh` still passes `--optimize-ane True`, while the open fix says that flag is broken and can load successfully but **SIGSEGV during inference**; removing it fixed transcription on an M4 Mac mini. [whispercpp-generate] [issue-3632]

There is one operational nuance worth calling out: the Hugging Face bucket already hosts prebuilt `ggml-*-encoder.mlmodelc.zip` artifacts, but the shipped `download-coreml-model.sh` starts with “this script hasn’t been maintained and is not functional atm”. So the artifacts exist, but upstream no longer ships a trustworthy fetch path for them. [hf-whispercpp] [download-coreml-script]

Assessment: **CoreML encoder support is real; ANE as a design assumption is not.** The docs’ `>x3` number is against CPU-only encoder execution, not against the Metal-backed path we would actually compare on Apple Silicon. The current evidence says the CoreML encoder path should be treated as optional and experimental, especially for `large-v3` / `large-v3-turbo`, not as the foundation of the design. [whispercpp-readme-coreml] [issue-2057] [issue-2126] [issue-3632]

## 3. Model file layout

| Runtime configuration | Files on disk | Notes |
| --- | --- | --- |
| `whisper.cpp` without CoreML | `ggml-<model>.bin` | Official download script pulls these from `https://huggingface.co/ggerganov/whisper.cpp`. This is the simplest deploy shape. [download-ggml] |
| `whisper.cpp` with CoreML encoder | `ggml-<model>.bin` plus sibling `ggml-<model>-encoder.mlmodelc/` | Upstream rewrites the model path to `-encoder.mlmodelc`, and it strips a trailing quant suffix like `-q5_0` before doing that. The HF bucket reflects this: e.g. `ggml-large-v3-q5_0.bin` exists next to `ggml-large-v3-encoder.mlmodelc.zip`, not a separate `-q5_0-encoder` zip. [src-whisper-coreml-path] [hf-whispercpp] |
| `#095` WhisperKit | Bundle directory such as `openai_whisper-tiny/` containing `AudioEncoder.mlmodelc/`, `MelSpectrogram.mlmodelc/`, `TextDecoder.mlmodelc/`, config JSON, and tokenizer files; turbo adds `TextDecoderContextPrefill.mlmodelc/` | Our landed WhisperKit descriptors validate multiple CoreML subtrees plus config/tokenizer files, and the adapter downloads the whole repo-folder bundle root (`<repoFolderName>/*`) plus tokenizer support files. [whisperkit-catalog] [whisperkit-adapter] |

Compared to `#095`, `whisper.cpp` is materially simpler on disk:

- Plain `whisper.cpp` is a single `.bin`.
- `whisper.cpp + CoreML` is still mostly a single-file runtime, with one optional sibling encoder directory.
- WhisperKit is an all-CoreML bundle layout with multiple compiled model directories plus config and tokenizer assets.

That difference matters for the design phase: if we pick `whisper.cpp`, the descriptor/store story can stay much closer to “one primary artifact, optional CoreML sidecar” than to WhisperKit’s “download and validate a whole bundle tree.” [src-whisper-coreml-path] [whisperkit-catalog] [whisperkit-adapter]

## 4. Recommendation

- **ANE path:** `No-go` as a phase-1 design commitment. Keep CoreML encoder support off the critical path and treat it as an optional later experiment.
- **Binding choice:** `Go` with a thin local Swift wrapper over upstream `whisper.h`, consumed via the upstream `whisper.cpp` XCFramework rather than `whisper.spm` or `SwiftWhisper`.
- **One-line design-phase next step:** design a `whisper.cpp` transcriber around a local `ggml-*.bin` model store, one serialized `whisper_context` per active model, and an optional `*-encoder.mlmodelc` sidecar that can be omitted by default.

**References**

[spm-readme]: https://github.com/ggerganov/whisper.spm/blob/master/README.md#L1-L17
[spm-package]: https://github.com/ggerganov/whisper.spm/blob/master/Package.swift#L23-L80
[spm-repo]: https://api.github.com/repos/ggerganov/whisper.spm
[spm-commit]: https://github.com/ggerganov/whisper.spm/commit/a2085436c2eb796af90956b62bd64731f5e5b823
[spm-prs]: https://github.com/search?q=repo%3Aggerganov%2Fwhisper.spm+is%3Apr+updated%3A%3E%3D2025-11-18&type=pullrequests
[swiftwhisper-repo]: https://api.github.com/repos/exPHAT/SwiftWhisper
[swiftwhisper-commit]: https://github.com/exPHAT/SwiftWhisper/commit/c340197966ebd264f3135d3955874b40f8ed58bc
[swiftwhisper-prs]: https://github.com/search?q=repo%3AexPHAT%2FSwiftWhisper+is%3Apr+updated%3A%3E%3D2025-11-18&type=pullrequests
[swiftwhisper-readme-usage]: https://github.com/exPHAT/SwiftWhisper/blob/master/README.md#L42-L49
[swiftwhisper-readme-coreml]: https://github.com/exPHAT/SwiftWhisper/blob/master/README.md#L75-L80
[swiftwhisper-package]: https://github.com/exPHAT/SwiftWhisper/blob/master/Package.swift#L11-L28
[swiftwhisper-whisper]: https://github.com/exPHAT/SwiftWhisper/blob/master/Sources/SwiftWhisper/Whisper.swift#L4-L190
[swiftwhisper-issue-37]: https://github.com/exPHAT/SwiftWhisper/issues/37
[swiftwhisper-issue-46]: https://github.com/exPHAT/SwiftWhisper/issues/46
[whispercpp-repo]: https://api.github.com/repos/ggml-org/whisper.cpp
[whispercpp-commit]: https://github.com/ggml-org/whisper.cpp/commit/6227a0ef739a78312d96e6f8f85e7b6d63683445
[whispercpp-prs]: https://github.com/search?q=repo%3Aggml-org%2Fwhisper.cpp+is%3Apr+updated%3A%3E%3D2025-11-18&type=pullrequests
[whispercpp-readme-coreml]: https://github.com/ggml-org/whisper.cpp/blob/master/README.md#L173-L228
[whispercpp-cmake]: https://github.com/ggml-org/whisper.cpp/blob/master/CMakeLists.txt#L91-L93
[whispercpp-generate]: https://github.com/ggml-org/whisper.cpp/blob/master/models/generate-coreml-model.sh#L27-L35
[whispercpp-xcframework]: https://github.com/ggml-org/whisper.cpp/blob/master/README.md#L723-L750
[whispercpp-build-xcframework]: https://github.com/ggml-org/whisper.cpp/blob/master/build-xcframework.sh#L428-L461
[whisper-h-basic]: https://github.com/ggml-org/whisper.cpp/blob/master/include/whisper.h#L45-L69
[whisper-h-context]: https://github.com/ggml-org/whisper.cpp/blob/master/include/whisper.h#L116-L214
[whisper-h-callbacks]: https://github.com/ggml-org/whisper.cpp/blob/master/include/whisper.h#L460-L652
[libwhisper]: https://github.com/ggml-org/whisper.cpp/blob/master/examples/whisper.swiftui/whisper.cpp.swift/LibWhisper.swift#L9-L18
[issue-1616]: https://github.com/ggml-org/whisper.cpp/issues/1616
[issue-1616-comment]: https://github.com/ggml-org/whisper.cpp/issues/1616#issuecomment-1867757449
[issue-2057]: https://github.com/ggml-org/whisper.cpp/issues/2057
[issue-2057-comment]: https://github.com/ggml-org/whisper.cpp/issues/2057#issuecomment-2057351041
[issue-2126]: https://github.com/ggml-org/whisper.cpp/issues/2126
[issue-2042]: https://github.com/ggml-org/whisper.cpp/issues/2042
[issue-2112]: https://github.com/ggml-org/whisper.cpp/issues/2112
[issue-2456]: https://github.com/ggml-org/whisper.cpp/issues/2456
[issue-2456-comments]: https://github.com/ggml-org/whisper.cpp/issues/2456#issuecomment-2395456197
[issue-3632]: https://github.com/ggml-org/whisper.cpp/pull/3632
[download-ggml]: https://github.com/ggml-org/whisper.cpp/blob/master/models/download-ggml-model.sh#L9-L149
[hf-whispercpp]: https://huggingface.co/ggerganov/whisper.cpp/tree/main
[download-coreml-script]: https://github.com/ggml-org/whisper.cpp/blob/master/models/download-coreml-model.sh#L1-L4
[src-whisper-coreml-path]: https://github.com/ggml-org/whisper.cpp/blob/master/src/whisper.cpp#L3327-L3343
[whisperkit-catalog]: ../../Sources/PersonalScribeCore/Models/Selection/BuiltInModelCatalog.swift#L147-L174
[whisperkit-adapter]: ../../Sources/PersonalScribeTranscription/Adapters/WhisperKitTranscriberAdapter.swift#L288-L309
