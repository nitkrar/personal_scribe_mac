# #095 — WhisperKit API Notes

Date: 2026-05-17

Purpose: Stage A.0 confirmation for the locked rev3 design. This note records the source-audited answers for:
- the SPM pin to use for `argmaxinc/argmax-oss-swift`
- the exact tokenizer lookup behavior when `modelFolder` is set

This was a source audit, not a runtime build. Santa/manifest execution blocked `swift build` in the temp clone, so the conclusions below are based on upstream code inspection.

## Audit inputs

- Fresh temp clone: `/tmp/whisperkit-audit-Ku42oX`
- Upstream repo: `https://github.com/argmaxinc/argmax-oss-swift.git`
- Tag checked: `v1.0.0`
- Commit at that tag: `25c62997041c134b03ca82731ce2f6fd2cae1eb9`
- Prior audit reference checkout: `/tmp/req-0115-WhisperKit`
- Prior audit reference commit: `984ab42f6d6824f17630109537829af26ca47fd6`

I diffed these four files between the fresh `v1.0.0` clone and the prior audit checkout:
- `Sources/WhisperKit/Core/Audio/AudioStreamTranscriber.swift`
- `Sources/ArgmaxCLI/TranscribeCLI.swift`
- `Sources/WhisperKit/Core/WhisperKit.swift`
- `Sources/WhisperKit/Utilities/ModelUtilities.swift`

All four diffs were empty.

## Pin decision

`v1.0.0` is the latest upstream tag as of the audit date, and the streaming/model-loading files relevant to #095 match the previously audited reference checkout on the paths above.

Decision:
- Pin `argmaxinc/argmax-oss-swift` to `exact: "1.0.0"`

Why this is safe enough for #095:
- It is the latest published tag.
- It matches the previously audited code on the exact files that matter for #095's adapter seam and tokenizer behavior.
- No re-audit of DESIGN.md section 2.1 is needed before implementation.

## Tokenizer lookup result

Short answer:
- `modelFolder` alone is not enough if Ninimma stages tokenizer files into `<modelsRoot>/<repoFolderName>/tokenizer/`.
- WhisperKit will find that pre-staged tokenizer only if Ninimma also passes `tokenizerFolder: <modelsRoot>/<repoFolderName>/tokenizer`.

### Source trace

1. `WhisperKit` stores `tokenizerFolder = config.tokenizerFolder ?? config.downloadBase`.
   - Source: `Sources/WhisperKit/Core/WhisperKit.swift:69`

2. When `modelFolder` is set, `loadTokenizerIfNeeded()` builds:
   - `additionalSearchPaths = [modelFolder] + [hubTokenizerFolderFromModel]`
   - where `hubTokenizerFolderFromModel` is `HubApiWrapper(downloadBase: modelFolder).localRepoLocation(tokenizerRepo)`
   - Source: `Sources/WhisperKit/Core/WhisperKit.swift:462-480`

3. `ModelUtilities.loadTokenizer(...)` then searches in this order:
   - `hubTokenizerFolder`
   - `tokenizerFolder` itself, if provided
   - `additionalSearchPaths`
   - Source: `Sources/WhisperKit/Utilities/ModelUtilities.swift:17-77`

4. `HubApi.localRepoLocation(_:)` resolves a repo to:
   - `<downloadBase>/<repo.type>/<repo.id>`
   - for model repos, that means `<downloadBase>/models/<repo.id>`
   - Source: `Sources/ArgmaxCore/External/Hub/HubApi.swift:350-352`

### Practical consequence for #095

Assume Ninimma's model leaf is:

```text
<modelsRoot>/<repoFolderName>/
```

and tokenizer files are pre-staged under:

```text
<modelsRoot>/<repoFolderName>/tokenizer/
```

If Ninimma passes only:

```swift
WhisperKitConfig(modelFolder: "<modelsRoot>/<repoFolderName>")
```

then WhisperKit does not search `<modelsRoot>/<repoFolderName>/tokenizer/` directly. The relevant local checks become:
- `<tokenizerFolder-or-downloadBase>/models/openai/whisper-*/tokenizer.json`
- `<modelFolder>/tokenizer.json`
- `<modelFolder>/models/openai/whisper-*/tokenizer.json`

That means the plain `<leaf>/tokenizer/` staging path is invisible unless `tokenizerFolder` is explicitly provided.

### Locked implementation consequence

For #095, the correct mechanism is:

1. Download the model bundle into staging, then move it into:

```text
<modelsRoot>/<repoFolderName>/
```

2. Download tokenizer files from the descriptor's `tokenizerSource` into:

```text
<modelsRoot>/<repoFolderName>/tokenizer/
```

3. Construct WhisperKit with both:

```swift
WhisperKitConfig(
    model: descriptor.repoFolderName,
    modelFolder: modelLeaf.path,
    tokenizerFolder: modelLeaf.appendingPathComponent("tokenizer"),
    download: false
)
```

This keeps tokenizer fetch offline after download, matches rev3 D5, and does not require any post-copy into WhisperKit's default HF cache layout.

## DESIGN.md impact

No blocker discovered against rev3 D4 or D5.

Confirmed:
- D4 still needs the two-step `snapshot -> move/copy into our leaf` flow.
- D5 is valid, and the concrete implementation path is the "WhisperKit exposes `tokenizerFolder`" branch that D5 already anticipated.

One implementation clarification is now locked:
- Stage B should pass `tokenizerFolder` explicitly instead of assuming `modelFolder` search will discover `<leaf>/tokenizer/`.
