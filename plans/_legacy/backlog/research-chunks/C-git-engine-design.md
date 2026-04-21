# C — Was `PrivateModelDownloader` designed engine-agnostic?

Research-only. Answers whether the custom downloader can be reused for a
future whisper.cpp / multilingual engine, or whether whisper.cpp will need
its own downloader regardless — i.e. whether deleting `PrivateModelDownloader`
today blocks multilingual.

## Git history — downloader

`git log --follow Sources/PersonalScribeTranscription/FluidAudioModelDownloader.swift`
shows 11 commits. Skipping mechanical renames (`5ce4984`) and the Stage-2
extraction/injection reshuffles (`aa49763`, `3905fd4`, `90b137f`), the load-
bearing commits all frame the downloader as a Parakeet/FluidAudio-specific
helper. No commit subject or body contains the words `whisper`, `multi-engine`,
`engine-agnostic`, `gguf`, or `ggml`.

- `0605de6` — `plan-03 step 1: pin fluidaudio dependency` — genesis is
  FluidAudio-specific.
- `fbddb20` — `plan-03 step 2: scaffold fluidaudio transcriber`.
- `5b73bdb` — `plan-03 step 4: pin model artifact revision` — pin is per-HF-
  repo, not per-engine-class.
- `a99bba4` — `plan-03 step 5: add model download progress state machine`.
- `cc050fd` — `plan-03 step 6: map model download failures`.
- `65b6210` — `plan-03 step 8: add model integrity validation` — brought in
  the CoreML-specific validation (see below).
- `990d5c3` — `phase-1 step 1.7: FluidAudio* take ModelDescriptor` — notable
  subject: types named `FluidAudio*` are what "take" the descriptor, not a
  neutral transcriber protocol. Test names `testDefaultInitializerUsesRegistryDefaultModelId`,
  `testDownloaderUsesPinnedRevision` confirm this.
- `aa49763` — `trunk: layer 6 — extract FluidAudio model-artifact statics to
  ModelArtifactStaging` — the extraction commit message explicitly scopes the
  5 statics as `FluidAudio` model-artifact statics, not generic.

No commit ever proposed turning `PrivateModelDownloader` into an engine-
abstract pipeline. The refactors since step 1.7 have been about Stage-2
injection/dependency-inversion (so tests can substitute a fake) — not about
swapping the download medium.

## Git history — descriptor / catalog

- `e6c9576` — `phase-1 step 1.5: ModelRegistry with Parakeet 0.6B v2 descriptor`
  — the initial registry was named and scoped for a single Parakeet model;
  test names include `testResolveURLUsesPinnedRepositoryRevisionAndRelativePath`
  — locking the HF URL shape as part of the contract from day one.
- `130d5e9` — `trunk: step model-selection.1 — Layer 6 Stage 1 parallel-build`
  — added `parakeetTDTCTC110M` and `parakeetTDT06Bv3` — both still Parakeet,
  both still FluidInference HF repos.
- `a3a0ba8` — `trunk: step model-selection.2 — Layer 6 Stage 2 consumer swap
  (descriptor-driven version selection)` — the generalization scope is
  explicitly "version selection" within Parakeet.
- `2191f09` — `trunk: stage 3 — layer 6 delete ModelRegistry, migrate to
  BuiltInModelCatalog` — extracted `TranscriptionEngine + ModelDescriptor` as
  "pure types, not registry" (see body: "Extracted TranscriptionEngine +
  ModelDescriptor (pure types, not registry) to Sources/SeshatCore/Models/
  Selection/ModelDescriptor.swift so they survive the registry deletion"). The
  engine enum is kept deliberately minimal; the commit does not introduce
  any new engine cases.

No commit body mentions whisper, ggml, gguf, llama.cpp, multilingual, or a
future non-HF fetch medium. The `TranscriptionEngine.whisper` / placeholder
commit never landed — the comment in `ModelDescriptor.swift:5-6` is the only
trace of the idea.

## TranscriptionEngine shape

`Sources/PersonalScribeCore/Models/Selection/ModelDescriptor.swift:3-7`:

```swift
public enum TranscriptionEngine: Sendable, Equatable {
    case parakeetTDT
    // Reserve shape for future engines (parakeetCTC, whisper, etc.).
    // Do not implement them now.
}
```

One case. The comment reserves the *enum shape* (i.e. "don't turn this into
a String" — callers can still exhaustively switch) for hypothetical future
engines but ships zero of them. Every `ModelDescriptor` in
`BuiltInModelCatalog.swift:19-54` assigns `engine: .parakeetTDT`
(`BuiltInModelCatalog.swift:26,40,53`).

Most tellingly, the `engine` field is read nowhere downstream that I can see
in the four audited files — the downloader does not switch on it, and
`ModelArtifactStaging` does not switch on it. The enum is currently a tag
with no behavioural contract.

## PrivateModelDownloader — HF-bound or engine-agnostic?

**Hard-coded to HuggingFace at the descriptor layer, not the downloader layer
— but the downloader is helpless without HF-shaped URLs.**

The downloader itself (`FluidAudioModelDownloader.swift:37-94`) is shaped
generically:

```swift
for (index, relativePath) in descriptor.requiredRelativePaths.enumerated() {
    …
    let request = URLRequest(url: descriptor.resolveURL(for: relativePath))
    let (bytes, response) = try await session.bytes(for: request)
```

It iterates `descriptor.requiredRelativePaths`, asks the descriptor to resolve
each one to a URL, and streams bytes with `URLSession`. Nothing in this loop
is Parakeet-specific — it would fetch any HTTPS resource.

The HF-hardcoding lives one level up, in `ModelDescriptor.resolveURL`
(`ModelDescriptor.swift:36-40`):

```swift
public func resolveURL(for relativePath: String) -> URL {
    URL(
        string: "https://huggingface.co/\(repository)/resolve/\(revision)/\(relativePath)"
    )!
}
```

This is not a protocol hook — it is a concrete struct method. Every
`ModelDescriptor` formats its URL as `huggingface.co/{repo}/resolve/{rev}/
{path}`. A whisper.cpp GGUF descriptor pointed at `ggerganov/whisper.cpp` on
HF would work; a GGUF blob hosted anywhere else (e.g. a self-hosted S3, a
CDN, a GitHub release) would require either forcing the URL into the
`repository` / `revision` fields dishonestly or changing the descriptor shape.

So:

- If whisper.cpp-on-HF is the only use case, `PrivateModelDownloader` reuses
  cleanly — it already streams arbitrary blobs with `URLSession.bytes(for:)`.
- The moment whisper.cpp artifacts need a different host, different auth, or
  redirect handling (HF uses `resolve/` which 302s to a CDN — the downloader
  does rely on `URLSession` following that redirect implicitly), the
  descriptor contract breaks and the downloader has to change.

There is **no `ModelDownloadStrategy` protocol, no `ArtifactSource` enum, no
URL-resolution injection** — `resolveURL` is a final method on a concrete
`public struct`. To add non-HF engines, someone has to either (a) add a case/
strategy, or (b) stop going through `resolveURL` and push the URL into the
descriptor directly.

## ModelArtifactStaging — CoreML-bound or generic?

The "exists" check is generic. The "valid" check is not.

`ModelArtifactStaging.modelsExist` (`ModelArtifactStaging.swift:15-19`) just
checks that every `descriptor.requiredRelativePaths` entry is a file on disk
— engine-agnostic.

`modelArtifactsAreValid` (`ModelArtifactStaging.swift:37-71`) is specifically
Parakeet-CoreML-shaped:

```swift
for path in requiredModelPaths(in: directory, descriptor: descriptor)
where path.lastPathComponent == "coremldata.bin" {
    guard
        let attributes = try? fileManager.attributesOfItem(atPath: path.path),
        let size = attributes[.size] as? NSNumber,
        size.intValue > 0
    else {
        return false
    }
}

let vocabURL = directory.appendingPathComponent("parakeet_vocab.json", isDirectory: false)
guard
    let data = try? Data(contentsOf: vocabURL),
    !data.isEmpty,
    let contents = String(data: data, encoding: .utf8)?
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .first,
    contents == "{" || contents == "["
else {
    return false
}
```

Two hard assumptions:

1. Filename `coremldata.bin` — CoreML compiled model internal format. Whisper
   GGUF files end `.gguf`; whisper.cpp `.bin` is a different magic number and
   would not be named `coremldata.bin`.
2. Filename `parakeet_vocab.json` with JSON-shaped first non-whitespace byte.
   Whisper's vocabulary is embedded in the GGUF/BIN itself; there is no
   external `parakeet_vocab.json` sibling file.

A whisper.cpp descriptor that declared `required_relative_paths = ["ggml-
base-q5_1.bin"]` would (a) pass `modelsExist` and (b) fail
`modelArtifactsAreValid` — the `parakeet_vocab.json` fetch would return nil
and the method would return `false`, causing endless re-download loops in
`FluidAudioTranscriber.ensureValidDownloadedModel` (`FluidAudioTranscriber.swift:
242-272`) which retries up to 2× then throws `modelDownloadFailure`.

`ModelAwareFluidAudioTranscriber` replicates the same check inline at
`ModelAwareFluidAudioTranscriber.swift:328-359` — same
`coremldata.bin` / `parakeet_vocab.json` hardcoding.

So the validator is CoreML+Parakeet-specific. Generalizing it would mean a
per-engine validation hook on the descriptor, or moving validation onto a
protocol the inference client owns.

## ModelDownloading protocol surface

From `FluidAudioTranscriber.swift:5-10`:

```swift
protocol ModelDownloading: Sendable {
    func ensureModelAvailable(
        at directory: URL,
        progress: @escaping @Sendable (ModelDownloadProgress) -> Void
    ) async throws -> URL
}
```

The protocol **surface itself is engine-agnostic** — `URL` in, `URL` out,
`ModelDownloadProgress` callback. Nothing names Parakeet, CoreML, HF, or
FluidAudio. A whisper.cpp downloader could trivially conform.

Caveats:

- The protocol is `internal` (no `public`), and lives inside
  `PersonalScribeTranscription`. It is not re-exported from `PersonalScribeCore`,
  so downstream engines would need to either import the transcription module
  or the protocol would need to be hoisted.
- `PrivateModelDownloader` takes `ModelDescriptor` in its init
  (`FluidAudioModelDownloader.swift:11-16`) — so the *implementation* is
  coupled to the HF-shaped descriptor, but the *protocol* isn't.
- `ModelDownloadProgress` (shape used by the callback) appears engine-neutral
  (phase + fraction + bytes) — nothing Parakeet-specific leaks.

Net: the protocol signature alone does not block a whisper.cpp plug-in.

## Conclusion

`PrivateModelDownloader` was designed to be **descriptor-driven, not
engine-agnostic.** The 300-line core loop would serve whisper.cpp if — and
only if — whisper.cpp artifacts are (a) on HuggingFace, (b) addressable via
`huggingface.co/{repo}/resolve/{rev}/{relativePath}`, and (c) representable
as a flat list of `requiredRelativePaths`. All three happen to be true for
most whisper.cpp GGUF distributions, so "technical fit" is plausible. However
the enforced download contract — `ModelArtifactStaging.modelArtifactsAreValid`
hard-coding `coremldata.bin` size > 0 and a JSON-shaped `parakeet_vocab.json`
— will reject every non-CoreML-Parakeet artifact and trigger the retry-then-
fail path in `ensureValidDownloadedModel`. That validator has to be made
pluggable (or owned by the inference client) **before** any non-Parakeet
engine can share the downloader. Given the validator rewrite and the non-
public `ModelDownloading` protocol are both prerequisites, a whisper.cpp
engine landing today would realistically either (a) ship its own downloader
or (b) gut & extend `ModelArtifactStaging` + hoist `ModelDownloading` to
public. Deleting `PrivateModelDownloader` now does not block multilingual —
the multilingual path needs validator+protocol changes regardless, and the
HTTP-streaming loop itself is ~50 lines of `URLSession.bytes(for:)` that any
new engine can trivially re-write against a cleaner abstraction rather than
inherit the current Parakeet-shaped descriptor coupling.
