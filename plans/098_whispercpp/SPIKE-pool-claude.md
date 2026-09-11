# #098 phase 1 — paper spike: whisper.cpp Swift binding + CoreML/ANE feasibility (pool-claude)

Independent research pass parallel to req-0007/codex-hermes. Source audit + docs + GitHub-issues triage; no code, no runtime benchmarks. All findings as of 2026-05-18, against whisper.cpp `master` (HEAD push 2026-05-18T07:18) and tagged release **v1.8.4** (2026-03-19).

---

## §1 — Swift binding comparison

### 1.1 At-a-glance

| Candidate | Source of truth | Last meaningful upstream activity | Stars / open issues | Status today | Couples to a whisper.cpp commit? |
|---|---|---|---|---|---|
| **A. `ggml-org/whisper.cpp` binary XCFramework** (per-release zip) | `github.com/ggml-org/whisper.cpp` README §"XCFramework" + `build-xcframework.sh` | 2026-05-18 (master), v1.8.4 tag 2026-03-19 | 49 823 / 1 196 (parent repo) | **Recommended path** — what the README now points to | Yes — version pin via release URL + SHA-256 |
| **B. `ggml-org/whisper.spm`** (legacy SPM wrapper) | `github.com/ggml-org/whisper.spm` | Last push 2024-05-27; README banner: **"THIS REPO WILL SOON BE ARCHIVED AND NO LONGER MAINTAINED"** | 189 / 5 | **Deprecated by upstream**; README redirects to whisper.cpp | Vendors a stale fork of whisper.cpp tree |
| **C. `exPHAT/SwiftWhisper`** | `github.com/exPHAT/SwiftWhisper` | Last commit **2023-08-17** (~2.7 years stale) | 778 / 12 | Effectively unmaintained; submodule pinned to whisper.cpp `95b02d76` from **2023-05-15** | Pins a 2023 whisper.cpp via git submodule; misses every fix since |
| **D. Direct C bridge** (`include/whisper.h`) | Same C ABI used by all of A/B/C | n/a — uses upstream `WHISPER_API` symbols directly | n/a | Always available; what every binding above already does | Whatever commit you build |

### 1.2 Detail per candidate

#### A. `ggml-org/whisper.cpp` binary XCFramework (the upstream-recommended path)

- `whisper.spm`'s README explicitly redirects users here: *"# THIS REPO WILL SOON BE ARCHIVED AND NO LONGER MAINTAINED — Please use the Swift package directly from whisper.cpp"* (`github.com/ggml-org/whisper.spm/blob/master/README.md` L1-L3).
- Upstream `README.md` §"XCFramework" gives the consumption pattern as a `.binaryTarget` referencing a release zip:
  ```swift
  // swift-tools-version: 5.10
  let package = Package(
      name: "Whisper",
      targets: [
          .executableTarget(name: "Whisper", dependencies: ["WhisperFramework"]),
          .binaryTarget(
              name: "WhisperFramework",
              url: "https://github.com/ggml-org/whisper.cpp/releases/download/v1.7.5/whisper-v1.7.5-xcframework.zip",
              checksum: "c7faeb328620d6012e130f3d705c51a6ea6c995605f2df50f6e1ad68c59c6c4a"
          )
      ]
  )
  ```
  (whisper.cpp `README.md` "## XCFramework" section, code block immediately after the heading.)
- The XCFramework is built by `build-xcframework.sh` at the repo root. Reading that script (`github.com/ggml-org/whisper.cpp/blob/master/build-xcframework.sh`):
  - Defaults: `GGML_METAL=ON`, `GGML_METAL_EMBED_LIBRARY=ON`, `GGML_BLAS_DEFAULT=ON`, `WHISPER_BUILD_EXAMPLES=OFF`, `WHISPER_BUILD_TESTS=OFF`.
  - **Builds with `WHISPER_COREML=ON` and `WHISPER_COREML_ALLOW_FALLBACK=ON`** (three `-DWHISPER_COREML="ON"` and `-DWHISPER_COREML_ALLOW_FALLBACK="ON"` entries per-slice in the script; visible via `grep -i coreml build-xcframework.sh`).
  - Adds `frameworks+=" -framework CoreML"` and links `libwhisper.coreml.a`.
  - Produces `build-apple/whisper.xcframework`.
- Latest tag **v1.8.4** ships `whisper-v1.8.4-xcframework.zip` (46.3 MB) under the GitHub release assets (verified via `gh api repos/ggml-org/whisper.cpp/releases/tags/v1.8.4` — asset listed alongside Windows / cuBLAS binaries; no JAR/SwiftPM source target needed).
- API surface exposed: same as direct C bridge — see §1.2.D.

#### B. `ggml-org/whisper.spm` (deprecated)

- Repo state: `archived: false` but README banner ("# THIS REPO WILL SOON BE ARCHIVED…") plus `pushed_at: 2024-05-27`. 189 stars, 5 open issues.
- `Package.swift` (swift-tools-version 5.3) **bakes in the same three CoreML flags** the build-xcframework.sh path uses:
  ```swift
  cSettings: [
      .unsafeFlags(["-Wno-shorten-64-to-32"]),
      .define("GGML_USE_ACCELERATE"),
      .define("WHISPER_USE_COREML"),
      .define("WHISPER_COREML_ALLOW_FALLBACK")
  ]
  ```
- But it **excludes Metal** at every architecture: `let exclude: [String] = ["Sources/whisper/ggml-metal.m", "Sources/whisper/ggml-metal.metal"]` with the inline comment `// TODO: make Metal work - I can't figure out how to build ggml-metal.m`. So even on Apple Silicon, the SPM build runs Accelerate-only CPU for any non-CoreML graph (no Metal). This is the chief technical reason upstream moved to the XCFramework path.
- `unsafeFlags` forces SPM consumers to use `branch: master` (per the linked issue #4 in the README) — Xcode rejects unsafe flags on tagged versions, so semver pinning isn't possible.
- Conclusion: deprecated, Metal-broken, no semver pinning. Don't adopt.

#### C. `exPHAT/SwiftWhisper`

- Last commit: **2023-08-17**. Last meaningful PRs are #39/#40 (2024-05-23, open, both author-only, no maintainer reply). Open issues from 2023→2025 all show the same pattern: filed, no response.
- `.gitmodules` pins `whisper.cpp` at submodule SHA **`95b02d76b04d18e4ce37ed8353a1f0797f1717ea`** which is the May 15 2023 commit *"coreml : add support of large-v1 model (#926)"*. That's three years stale — no `large-v3`/`large-v3-turbo` support, no Flash Attention, no Metal embed, no quantization formats added since (`q5_0`, `q5_1`, `q8_0` for large-v3-turbo all post-date this commit).
- `Package.swift` declares Linux exclusion but matches the same three CoreML flags whisper.spm did:
  ```swift
  cSettings: [
      .define("GGML_USE_ACCELERATE", .when(...)),
      .define("WHISPER_USE_COREML", .when(...)),
      .define("WHISPER_COREML_ALLOW_FALLBACK", .when(...))
  ]
  ```
- Exposes a Swift convenience layer (`Whisper`, `WhisperDelegate`, `transcribe(audioFrames:) async throws -> [Segment]`) which is shaped opinionated — single-shot, file-URL model loader, fixed VAD-less pipeline. The README's CoreML section confirms the file-naming convention is the same as upstream (`tiny.bin` next to `tiny-encoder.mlmodelc`).
- Conclusion: nicer Swift sugar, but stuck on a 2023 codebase. Will not transcribe `large-v3-turbo` correctly. Unmaintained. Don't adopt.

#### D. Direct C bridge (cross-cutting — what A actually exposes)

- Public header: `github.com/ggml-org/whisper.cpp/blob/master/include/whisper.h`. Single header; one declaration block under `extern "C"`. Imports `ggml.h` and `ggml-cpu.h` (which the XCFramework bundles).
- Core surface (verified via `grep "^\s\+WHISPER_API" include/whisper.h`):
  - **Context lifecycle:** `whisper_init_from_file_with_params`, `whisper_init_from_buffer_with_params`, `whisper_init_with_params` (and `_no_state` variants), `whisper_init_state`, `whisper_free`, `whisper_free_state`, `whisper_free_params`, `whisper_free_context_params`.
  - **Decode pipeline (high-level):** `whisper_full(ctx, params, samples, n_samples)` is the one-call path; produces N segments retrievable via `whisper_full_n_segments` / `whisper_full_get_segment_text` / `whisper_full_get_segment_t0`/`_t1` / `whisper_full_get_token_*`.
  - **Decode pipeline (low-level):** `whisper_pcm_to_mel`, `whisper_set_mel`, `whisper_encode`, `whisper_decode`, `whisper_tokenize`. Lets you drive the encode and decode steps separately (useful for VAD-driven streaming).
  - **Language ID:** `whisper_lang_auto_detect`, `whisper_lang_id`, `whisper_lang_str`, etc.
  - **OpenVINO toggle:** `whisper_ctx_init_openvino_encoder` (irrelevant on Apple Silicon — we won't link OpenVINO).
- `whisper_full_params` (struct) exposes everything we'd need for the Transcriber protocol:
  - `language` (const char *), `detect_language`, `translate`, `temperature`, `temperature_inc`, `n_threads`, `offset_ms`, `duration_ms`, `single_segment`, `print_realtime` (advised off), `suppress_blank`, `suppress_non_speech_tokens`, `initial_prompt`, `prompt_tokens` / `prompt_n_tokens`, `entropy_thold`, `logprob_thold`, `no_speech_thold`.
  - **Callbacks** (all `void * user_data`-style): `whisper_new_segment_callback`, `whisper_progress_callback`, `whisper_encoder_begin_callback`, `whisper_logits_filter_callback`. Plenty for streaming partial-segment delivery + progress hooks + cancellation (returning `false` from `encoder_begin_callback` aborts the encode).
- Sample Swift consumption pattern in `examples/whisper.swiftui/whisper.cpp.swift/LibWhisper.swift` (in-tree, MIT-licensed reference):
  - Uses `actor WhisperContext` wrapping `OpaquePointer`.
  - Calls C functions directly via the imported `whisper` module (no Swift wrapper layer).
  - Sets `params.use_gpu = false` for simulator builds; `params.flash_attn = true` otherwise.
  - Pattern: `samples.withUnsafeBufferPointer { whisper_full(ctx, params, $0.baseAddress, Int32($0.count)) }`.
- **Thread-safety note**: header docstring says *"The following interface is thread-safe as long as the sample whisper_context is not used by multiple threads concurrently."* → must serialize per-context (the `actor` pattern in LibWhisper.swift is the upstream-blessed way).

### 1.3 Recommendation for binding choice

**Adopt path A — binary XCFramework from `ggml-org/whisper.cpp` releases — and add a thin Swift wrapper in our own code modeled on the in-tree `LibWhisper.swift` example.** Rationale:

1. **Upstream-canonical.** The redirect in whisper.spm's README is explicit; this is where maintenance lives. We get the same C API as paths B/C/D but with all Apple-platform build flags (CoreML, Metal, Accelerate, BLAS) already correct.
2. **Semver-pinnable.** `.binaryTarget(url:..., checksum:...)` against a tagged release zip (e.g. v1.8.4) is reproducible and SPM-friendly. Path B can't do this (unsafe-flags constraint forces `branch: master`).
3. **No vendor lock-in.** The wrapper we write is ~150 lines of Swift around `whisper_full` + callbacks — same code we'd write under any binding. If upstream ever ships a first-party Swift package, swap the binaryTarget for the source SPM target with zero call-site changes.
4. **Transcriber-protocol fit.** All the descriptors-bound state (model path, language, prompts, temperature, segment callbacks) flows through `whisper_full_params`. No path B/C-style impedance mismatch.

Reject path B: deprecated, Metal-broken. Reject path C: 2.7 years stale, no large-v3-turbo. The "direct C bridge with our own bridging-header" framing (path D in the original question) is really *how* you consume path A — it's not a separate option.

---

## §2 — CoreML / ANE feasibility

### 2.1 What the docs claim

From upstream `README.md` § "Core ML support" (last edited within current release cycle):

> "On Apple Silicon devices, the Encoder inference can be executed on the Apple Neural Engine (ANE) via Core ML. This can result in significant speed-up — **more than x3 faster** compared with CPU-only execution."

Key qualifiers in that section:
- "**Encoder** inference" only — decoder always stays on the ggml/Metal/CPU graph (confirmed by `models/generate-coreml-model.sh` which still has `# TODO: decoder (sometime in the future maybe)` for the decoder step).
- Build flag: `cmake -B build -DWHISPER_COREML=1`. README example.
- Companion file: generation script produces `models/ggml-<name>-encoder.mlmodelc` (a compiled Core ML model directory, not a single file).
- *"The first run on a device is slow, since the ANE service compiles the Core ML model to some device-specific format. Next runs are faster."*
- The "x3 faster" baseline is **CPU-only**, not Metal. Comparing CoreML/ANE vs Metal (which is what Apple Silicon would otherwise use) is *not* what the README is measuring.

The original PR #566 (March 2023) carries a community benchmark from a Mac Mini M2 showing the encoder dropping from 980 ms → 190 ms on the `small` model (≈5× encoder-only speedup). That number is the source of the "more than x3" claim, but the table is only `tiny` / `base` / `small` — medium and large rows are blank.

### 2.2 What real users report (issues, in chronological order)

| Issue | Date | Hardware / model | Result | Source |
|---|---|---|---|---|
| **#1616** "Why coreml is so slow?" | 2023-12-10 | unspecified Mac | **36s with CoreML vs 13s without** for a short sentence — net **slowdown** | `github.com/ggml-org/whisper.cpp/issues/1616` |
| **#2057** "It seems that there is no performance gain utilizing Core ML" | 2024-04-15 | Mac, `ggml-medium.bin`, 8-min audio | CoreML encode 6 931 ms / 21 runs vs non-CoreML 5 827 ms / 21 runs — CoreML is actually **slower per encode**; total times within ~5% of each other | `github.com/ggml-org/whisper.cpp/issues/2057` |
| **#2126** "Every run with CoreML 'first run on a device may take a while ...'" | 2024-05-06 | macOS 14.4.1, `ggml-small.en` | Compile-cache claim breaks: three sequential runs all take ~25s as if first-run each time | `github.com/ggml-org/whisper.cpp/issues/2126` |
| **#2456** "large-v3-turbo run with coreml on iPhone XR Apple A12 Bionic not generating correct text" | 2024-10-05 | iPhone XR (A12), `large-v3-turbo` | **Output gibberish** ("A, SATR,man,gost E.") with CoreML on older ANE — accuracy regression, not just speed | `github.com/ggml-org/whisper.cpp/issues/2456` |
| **#2696** turbo segments dropped | 2025-01-02 | various | turbo + CoreML drops short conversations from long-form audio | `github.com/ggml-org/whisper.cpp/issues/2696` |
| **#3702** "ANE inference fails on M4 + macOS 26.4 beta with CoreML encoder" | 2026-03-11 | MacBook Air M4, macOS 26.4 beta, `large-v3-turbo-q5_0`, whisper.cpp v1.8.3 | ANE compilation fails: `ANE inference operation failed due to unknown error. @ EvaluateANERequest / E5RT encountered an STL exception. msg = MILCompilerForANE error: failed to compile ANE model using ANEF.` → silently falls back to Metal GPU, **~2-3× slower than expected ANE**. Reproducer says fail rate is independent of `--optimize-ane True/False`. | `github.com/ggml-org/whisper.cpp/issues/3702` |
| **#3745** "RuntimeError: BlobWriter not loaded" | 2026-04-05 | Python toolchain | the `generate-coreml-model.sh` script itself fails when generating large-v3 due to `coremltools` packaging issues (`No module named 'coremltools.libcoremlpython'`) on recent Python/Torch versions | `github.com/ggml-org/whisper.cpp/issues/3745` |

**The single most damaging finding** (PR #3632, opened 2026-01-29, still open as of today):

> The `generate-coreml-model.sh` script currently passes `--optimize-ane True` to the conversion script, but this flag is explicitly marked as broken:
> ```python
> parser.add_argument("--optimize-ane", type=bool, help="optimize for ANE execution (currently broken)", default=False)
> ```
> When `--optimize-ane True` is used, the generated CoreML models: 1. Load successfully — whisper.cpp reports `Core ML model loaded`. 2. **Crash during inference — SIGSEGV when processing audio.** … Tested on M4 Mac mini with large-v3-turbo model: Before: SIGSEGV crash during inference. After [removing the flag]: Model loads and transcribes correctly with `COREML = 1`.

I verified the present-day script in repo (`models/generate-coreml-model.sh` L29) still has the broken-by-default line:
```sh
python3 models/convert-whisper-to-coreml.py --model "$mname" --encoder-only True --optimize-ane True
```
and `models/convert-whisper-to-coreml.py` L299 still has the warning comment:
```python
parser.add_argument("--optimize-ane", type=bool, help="optimize for ANE execution (currently broken)", default=False)
```
PR #3632 has been open and unmerged for ~4 months.

The second-most damaging finding (often missed):

```sh
# models/download-coreml-model.sh, lines 1-4
#!/bin/sh
printf "whisper.cpp: this script hasn't been maintained and is not functional atm\n"
exit 1
```

The official **pre-built CoreML model download script is a no-op stub**. Any CoreML model must be generated locally from Python with `coremltools` + `ane_transformers` + `openai-whisper` (and per #3745 that's now broken on recent toolchains). This is a hard friction for distributing models to end users — we'd have to host our own pre-built `.mlmodelc` directories somewhere.

### 2.3 Does the chosen binding (path A XCFramework) expose CoreML?

**Yes.** `build-xcframework.sh` passes `-DWHISPER_COREML="ON"` and `-DWHISPER_COREML_ALLOW_FALLBACK="ON"` to every slice (macOS, iOS, iOS-sim, visionOS, tvOS — `grep "WHISPER_COREML" build-xcframework.sh` shows three pairs of these defines, one per slice). The released v1.7.5 / v1.8.4 zips link `libwhisper.coreml.a` and `-framework CoreML`. So:
- The framework as shipped will **try CoreML** if a sibling `ggml-<name>-encoder.mlmodelc` directory exists next to the `.bin`.
- If the mlmodelc isn't there, `WHISPER_COREML_ALLOW_FALLBACK=ON` means whisper.cpp keeps running the encoder on ggml/Metal/CPU instead of failing — i.e. **shipping without the mlmodelc is safe**; the runtime degrades gracefully.

How whisper.cpp finds the file (`src/whisper.cpp` `whisper_get_coreml_path_encoder()`):
```cpp
// replace .bin with -encoder.mlmodelc, after also stripping a -qX_X quant suffix
// so ggml-large-v3-turbo-q5_0.bin → ggml-large-v3-turbo-encoder.mlmodelc
```
i.e. **the encoder.mlmodelc is shared across quantization variants** of the same base model — important for our model-store sizing.

How the encoder.mm runs it (`src/coreml/whisper-encoder.mm` `whisper_coreml_init`):
```objc
MLModelConfiguration *config = [[MLModelConfiguration alloc] init];
// config.computeUnits = MLComputeUnitsCPUAndGPU;
// config.computeUnits = MLComputeUnitsCPUAndNeuralEngine;
config.computeUnits = MLComputeUnitsAll;
```
That is, the upstream lets Core ML **pick** between CPU / GPU / ANE — it does not force ANE. The OS may schedule the encoder onto the GPU even when ANE is requested (which is exactly the failure path #3702 describes when ANE compilation errors out).

### 2.4 Honest go/no-go on the ANE path

**No-go for shipping ANE as a hard dependency. Go for ANE as an opportunistic optimization with a CoreML-disabled control path.**

Synthesizing the above:

- The "x3 ANE speedup" claim is a **CPU-only baseline** comparison from 2023 on small models. The realistic comparison for us — CoreML/ANE encoder vs Metal encoder on Apple Silicon, with `large-v3-turbo` weights — has no upstream-published benchmark and the available user reports are mixed-to-negative (#2057, #1616) or actively broken (#3702 on M4 + macOS 26.x, #2456 accuracy on A12, #3632 official script produces crashing models).
- **`large-v3` / `large-v3-turbo` (the models we actually care about for transcription quality) are the worst-supported ANE configurations.** The `--optimize-ane` codepath is broken; the non-ANE-optimized CoreML model still runs through Core ML but lets the OS schedule the encoder wherever it wants (often GPU, not ANE). For `large-v3-turbo` specifically, the encoder is already a small fraction of total time (the decoder dominates because turbo cuts decoder layers, not encoder), so a 3× encoder-only speedup translates to maybe 5-15% wall-clock on long audio — not the headline number.
- Distribution friction: no working pre-built CoreML download path means we'd own model conversion ourselves (broken toolchain per #3745) or skip CoreML.

**Recommended decision:** build the XCFramework as upstream ships it (CoreML on with fallback). Ship `.bin` only by default — no `.mlmodelc`. Provide an optional, advanced "Generate CoreML encoder" path later if benchmarks justify it. This matches how #095 (WhisperKit) and #098 (whisper.cpp) would A/B fairly: both use the same `.bin` weights, but #095 routes them through WhisperKit's all-CoreML pipeline while #098 routes them through whisper.cpp's Metal/CPU pipeline. **That comparison answers the actual user-facing question** ("which runtime is faster on my Mac?") much more cleanly than spending the spike phase chasing a broken ANE path.

---

## §3 — Model file layout

### 3.1 whisper.cpp ggml format

- **File format:** `ggml-<name>.bin` — a single binary blob in whisper.cpp's `ggml` format (not a directory). Contains both encoder and decoder weights. Format is whisper.cpp's own (see `models/README.md` and `models/convert-pt-to-ggml.py`).
- **Distribution bucket:** `https://huggingface.co/ggerganov/whisper.cpp` (`pfx="resolve/main/ggml"`). The official downloader script `models/download-ggml-model.sh` derives URLs as:
  ```
  https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-<name>.bin
  ```
  Example for our likely shortlist:
  - `ggml-large-v3-turbo.bin` (1.5 GiB, sha `4af2b29d…`)
  - `ggml-large-v3-turbo-q5_0.bin` (~570 MiB; q5_0 quant)
  - `ggml-large-v3-turbo-q8_0.bin`
  - `ggml-large-v3.bin` (2.9 GiB, sha `ad82bf6a…`) / `ggml-large-v3-q5_0.bin` (1.1 GiB)
  - `ggml-medium.en.bin` (1.5 GiB) / `ggml-medium.en-q5_0.bin`
- **Quantization is encoded in the filename suffix** (`-q5_0`, `-q5_1`, `-q8_0`). Available quants vary per base model — full list of pre-built ones in `models/download-ggml-model.sh` (30 entries).

### 3.2 Optional CoreML encoder sibling

- **Naming convention** (from `whisper_get_coreml_path_encoder()` in `src/whisper.cpp`): `ggml-<name>-encoder.mlmodelc`. The `.mlmodelc` is a **compiled CoreML model directory**, not a single file (output of `xcrun coremlc compile`).
- **Co-location rule:** must live in the same directory as the `.bin`. The path is computed from the bin path by replacing the suffix.
- **Quantization-stripping**: the path resolver strips a `-qX_X` suffix before appending `-encoder.mlmodelc`, so `ggml-large-v3-turbo-q5_0.bin` looks up `ggml-large-v3-turbo-encoder.mlmodelc` (same encoder file for all quants of one base model). Practical: one ~30-300MB encoder.mlmodelc shared across all your quant variants of `large-v3-turbo`.
- **No pre-built bucket**: `models/download-coreml-model.sh` is a stub (`exit 1`, "not functional atm"). The dataset URL it points to (`huggingface.co/datasets/ggerganov/whisper.cpp-coreml`) returns 404 / not-found territory.
- **Generation**: `models/generate-coreml-model.sh <model-name>` runs `convert-whisper-to-coreml.py` (Python; needs `ane_transformers`, `openai-whisper`, `coremltools`, recommended Python 3.11, macOS Sonoma+). **Caveat per §2.2**: the default flags produce a broken-on-ANE model (PR #3632). Workaround until that PR merges is to manually edit the shell script to drop `--optimize-ane True`.

### 3.3 Comparison vs #095 WhisperKit layout

| Aspect | #098 whisper.cpp (proposed) | #095 WhisperKit (shipped) |
|---|---|---|
| **Leaf directory on disk** | `<modelsRoot>/<repoFolderName>/` | `<modelsRoot>/<repoFolderName>/` (same canonical leaf invariant) |
| **Repo on Hugging Face** | `ggerganov/whisper.cpp` (single repo, all model files at root) | `argmaxinc/whisperkit-coreml` (single repo, one subdir per bundle) |
| **`repoFolderName` example** | `ggml-large-v3-turbo` (per-model) | `openai_whisper-large-v3-turbo` (per-bundle) |
| **Required file(s) on disk** | `ggml-<name>.bin` (single file, optional `-encoder.mlmodelc` dir sibling) | `AudioEncoder.mlmodelc/`, `TextDecoder.mlmodelc/`, `MelSpectrogram.mlmodelc/`, `config.json`, `generation_config.json` |
| **Tokenizer** | **Embedded in the `.bin`** — no separate tokenizer file needed | Separate tokenizer download from `openai/whisper-*` repo into `<modelsRoot>/<repoFolderName>/tokenizer/tokenizer.json` |
| **Number of files to download per model** | 1 (.bin) — or 2 (bin + encoder.mlmodelc directory) if CoreML | 4-6 files for bundle + tokenizer (per #095 IMPLEMENTATION.md) |
| **Quant variant handling** | Filename suffix `-qX_X`; each quant is a separate `.bin`; `.mlmodelc` shared across quants | WhisperKit ships separate bundles per quant (e.g. `openai_whisper-large-v3-turbo`, `…-large-v3-turbo-632MB`) — no shared assets |
| **Disk footprint, large-v3-turbo @ q5_0** | ~570 MiB (.bin) + optional ~100-200 MiB encoder.mlmodelc | ~632 MiB bundle (per #095's `whisperkit-large-v3-turbo-632mb`) + tokenizer |
| **`isDownloaded` predicate** | Existence of `ggml-<name>.bin` (and `-encoder.mlmodelc/coremldata.bin` if CoreML expected) | Existence of all three `.mlmodelc/coremldata.bin` files + `config.json` + tokenizer (per `requiredRelativePaths` in #095 design) |
| **Inference path** | C library; explicit `whisper_full(...)` actor-serialized | WhisperKit class; `transcribe(audioArray:)` async |
| **HF API used** | Plain HTTPS GET of `huggingface.co/.../resolve/main/<file>` — no auth | `HubApi.snapshot(repoID:matching:downloadBase:)` (vendored from huggingface-swift) |

**Implication for the Ninimma adapter shape:**

- We can keep the same `repoFolderName`-as-cache-anchor invariant from #095. The whisper.cpp adapter would set `repoFolderName: "ggml-large-v3-turbo"` (or similar), `requiredRelativePaths: ["ggml-large-v3-turbo-q5_0.bin"]`, `repository: "ggerganov/whisper.cpp"`.
- Download is *simpler* than #095: a single HTTPS GET, no HubApi staging-and-move dance, no separate tokenizer download. The bug that bit #095 (HubApi.snapshot's `downloadBase:` not honoring arbitrary destinations) doesn't exist here.
- We may want a second descriptor flag like `coremlEncoderFilename: String?` for the optional sibling. Most descriptors set it `nil` initially; advanced users can opt-in later.

---

## §4 — Recommendation & one-line next-phase summary

**Recommendation (go/no-go bundle):**

1. **Binding choice → adopt `ggml-org/whisper.cpp` binary XCFramework via `.binaryTarget`**, pinned to a tagged release (start with v1.8.4 — March 2026, has the relevant turbo + Metal-flash-attn maturity). Add a thin Swift wrapper (~150 lines, modeled on the in-tree `examples/whisper.swiftui/whisper.cpp.swift/LibWhisper.swift`) wrapping `whisper_init_from_file_with_params` + `whisper_full` + the four callbacks. Reject whisper.spm (deprecated, no Metal). Reject SwiftWhisper (3 yrs stale, no large-v3-turbo).
2. **ANE path → NO-GO as a hard dependency, opportunistic-only.** Ship CoreML compiled in (XCFramework already does that with `WHISPER_COREML_ALLOW_FALLBACK=ON`), but ship models as `.bin` only — no `.mlmodelc` bundled. Issues #3702, #3632, #2057, #1616, #2456 plus the broken official tooling (PR #3632 4-months unmerged, download script disabled, generation script broken on recent toolchains per #3745) make ANE too unreliable to be a load-bearing claim for users. The genuine A/B test we want — whisper.cpp Metal vs WhisperKit CoreML on identical Whisper weights — is the productive comparison; bench-chasing ANE is not.
3. **Model file layout → simpler than #095.** Single `.bin` per descriptor at `<modelsRoot>/<repoFolderName>/ggml-<name>.bin`, fetched from `https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-<name>.bin` via plain HTTPS. Tokenizer is embedded in the .bin → no separate download flow. Quant variants are separate `.bin`s named by suffix.

**One-line next-phase summary:** Design phase needs to decide (a) which subset of `ggml-large-v3-turbo*`, `ggml-large-v3*`, `ggml-medium.en*` quants to expose as descriptors (likely just `large-v3-turbo-q5_0` + `large-v3-turbo` to start, mirroring #095's tier), and (b) the Transcriber-protocol-level streaming contract — i.e. whether `whisper_new_segment_callback` events get bridged into the same partial-segment delivery shape #095 emits, or whether whisper.cpp's coarser segment cadence requires a different surface.
