# Plan 01: SPM Project Setup (v2)

**Goal**: create the Week 1 Swift Package scaffold and nothing else.
**Architecture**: `SeshatAppKit` executable target, five supporting libraries, five XCTest targets, repo initialized with git.
**Tech Stack**: Swift Package Manager, Swift 6 tools version, XCTest, git.
**Depends on**: none.
**Authoritative inputs read**: Plan 01 v1, the Codex review of v1, Plan 00 final, Plans 02/03/04/99.

## Changes from v1 → v2

- Review Critical Issue 1: Step 3 now restates the non-`Composition/` `SeshatAppKit` import boundary and adds the required grep verification.
- Review Critical Issue 2: Step 3 is split into `3.1`–`3.8`; Step 4 is split into `4.1`–`4.5`; each substep has its own verification and commit.
- Review Suggestion 1: Steps 7 and 8 are now verification gates only. No fake red-green framing remains.
- Review Suggestion 2: manifest sequencing is explicit. Step 2 ships an interim manifest; Step 5 amends it to the final manifest shown below.
- Round 4 requirement: this revision adds `Forbidden Duplicates Semantic Audit`, `Sibling Cross-Plan Audit`, and `Self-verification Checklist`.
- No review finding is rejected in v2.

## Changes in v2.1 (Claude meta-review fix)

- Step 3.7: the app-shell placeholder is no longer a `@main struct SeshatApp: App` — it is now an inert `public enum SeshatAppPlaceholder {}`. Plan 04 v2 explicitly forbids `@main` in `Sources/SeshatAppKit/` (line 875, 1030, 1037); Plan 99 ships the first `@main`. The v1 parallel-authoring setup had each reviser read the other's v1 only, so this cross-plan mismatch surfaced at meta-review. The placeholder is now file-path-only: Plan 04 Step 10 overwrites the file with the real injectable shell (still no `@main`), and Plan 99 creates a separate `@main` entry point.
- Step 3.7 verification now includes `grep -r "@main" Sources/SeshatAppKit/` which MUST print nothing after Plan 01 completes.
- Forbidden Duplicates Semantic Audit rows for `SeshatApp` and `AppDelegate` are updated to reflect the placeholder-only shape.
- Sibling Cross-Plan Audit Plan 04 section gains an explicit `@main` check.

## A. Hard Guardrails

- Plan 01 creates only inert scaffolding.
- Plan 01 must not define any Plan 00 Section C symbol.
- Plan 01 must not define any wrapper protocol around a Plan 00 concept.
- Plan 01 must not create `Sources/SeshatAppKit/Composition/AppComposition.swift`.
- Plan 01 must not pin FluidAudio.
- Library placeholder files use only `public enum <Target>Module {}`.
- `SeshatAppKit` placeholder files are disposable shells only.
- Non-`Composition/` `SeshatAppKit` files must not import `SeshatAudio` or `SeshatTranscription`.

## B. Reference Artifacts

### Final `Package.swift` after Step 5

```swift
// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Seshat",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "SeshatCore",
            targets: ["SeshatCore"]
        ),
        .library(
            name: "SeshatAudio",
            targets: ["SeshatAudio"]
        ),
        .library(
            name: "SeshatTranscription",
            targets: ["SeshatTranscription"]
        ),
        .library(
            name: "SeshatSession",
            targets: ["SeshatSession"]
        ),
        .library(
            name: "SeshatTestSupport",
            targets: ["SeshatTestSupport"]
        ),
        .executable(
            name: "SeshatAppKit",
            targets: ["SeshatAppKit"]
        ),
    ],
    dependencies: [
        // TODO(plan-03): After verifying the upstream repository URL, package identity,
        // product name, and exact version, add the pinned FluidAudio dependency here.
        // Do not guess or ship an unverified dependency declaration in Plan 01.
        // .package(url: "<verified-fluid-audio-url>", exact: "<verified-version>"),
    ],
    targets: [
        .target(
            name: "SeshatCore",
            path: "Sources/SeshatCore"
        ),
        .target(
            name: "SeshatAudio",
            dependencies: [
                "SeshatCore",
            ],
            path: "Sources/SeshatAudio"
        ),
        .target(
            name: "SeshatTranscription",
            dependencies: [
                "SeshatCore",
                // TODO(plan-03): After pinning FluidAudio above, add:
                // .product(name: "<verified-product-name>", package: "<verified-package-name>"),
            ],
            path: "Sources/SeshatTranscription"
        ),
        .target(
            name: "SeshatSession",
            dependencies: [
                "SeshatCore",
                "SeshatAudio",
                "SeshatTranscription",
            ],
            path: "Sources/SeshatSession"
        ),
        .target(
            name: "SeshatTestSupport",
            dependencies: [
                "SeshatCore",
            ],
            path: "Sources/SeshatTestSupport"
        ),
        .executableTarget(
            name: "SeshatAppKit",
            dependencies: [
                "SeshatCore",
                "SeshatSession",
                "SeshatAudio",
                "SeshatTranscription",
            ],
            path: "Sources/SeshatAppKit"
        ),
        .testTarget(
            name: "SeshatCoreTests",
            dependencies: [
                "SeshatCore",
            ],
            path: "Tests/SeshatCoreTests"
        ),
        .testTarget(
            name: "SeshatAudioTests",
            dependencies: [
                "SeshatAudio",
                "SeshatTestSupport",
            ],
            path: "Tests/SeshatAudioTests"
        ),
        .testTarget(
            name: "SeshatTranscriptionTests",
            dependencies: [
                "SeshatTranscription",
                "SeshatTestSupport",
            ],
            path: "Tests/SeshatTranscriptionTests"
        ),
        .testTarget(
            name: "SeshatSessionTests",
            dependencies: [
                "SeshatSession",
                "SeshatTestSupport",
            ],
            path: "Tests/SeshatSessionTests"
        ),
        .testTarget(
            name: "SeshatAppKitTests",
            dependencies: [
                "SeshatAppKit",
                "SeshatTestSupport",
            ],
            path: "Tests/SeshatAppKitTests"
        ),
    ],
    swiftLanguageModes: [
        .v6,
    ]
)
```

### Final `.gitignore`

```gitignore
.DS_Store
/.build
/.swiftpm
/Packages
xcuserdata/
DerivedData/
*.xcodeproj
.netrc
```

### Placeholder code shapes

Library placeholder:

```swift
public enum SeshatCoreModule {}
```

App shell placeholder (inert — NO `@main`, NO `App` conformance; Plan 04 writes the real shell, Plan 99 writes the `@main` entry point):

```swift
public enum SeshatAppPlaceholder {}
```

Delegate placeholder (inert; Plan 04 decides whether `AppDelegate` is needed — Plan 04 v2 currently removes it):

```swift
public enum AppDelegatePlaceholder {}
```

**Why no `@main` here**: Plan 04 v2 Section H.3 and the Plan 04 handoff both explicitly forbid `@main` in `Sources/SeshatAppKit/`. Plan 99 ships the first `@main` after Plans 02–04 complete. If Plan 01 scaffolds `@main`, it either (a) makes the executable target "runnable" with a shell Plan 04 has to delete, or (b) creates a conflict when SPM sees two `@main` declarations after Plan 99. Keeping Plan 01's placeholder inert avoids both.

No-op XCTest placeholder:

```swift
import XCTest
@testable import SeshatCore

final class SeshatCorePlaceholderTests: XCTestCase {
    func testPlaceholder() { XCTAssertTrue(true) }
}
```

## C. Task Breakdown

### Step 1. Initialize repo scaffold

**Time**: 3–5 minutes.
**Files**: `.gitignore`, `.git/`.

- Run `git init`.
- Add `.gitignore` exactly as shown above.
- Stage only `.gitignore`.

Verification:

```bash
git rev-parse --is-inside-work-tree
test -f .gitignore
git status --short
```

Commit:

```bash
git add .gitignore
git commit -m "plan-01 step 1: initialize repository scaffolding"
```

### Step 2. Add the interim `Package.swift`

**Time**: 4–5 minutes.
**Files**: `Package.swift`.
**Rule**: Step 2 declares the full target graph but does not yet add the FluidAudio TODO comments or `swiftLanguageModes`.

```swift
// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Seshat",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "SeshatCore",
            targets: ["SeshatCore"]
        ),
        .library(
            name: "SeshatAudio",
            targets: ["SeshatAudio"]
        ),
        .library(
            name: "SeshatTranscription",
            targets: ["SeshatTranscription"]
        ),
        .library(
            name: "SeshatSession",
            targets: ["SeshatSession"]
        ),
        .library(
            name: "SeshatTestSupport",
            targets: ["SeshatTestSupport"]
        ),
        .executable(
            name: "SeshatAppKit",
            targets: ["SeshatAppKit"]
        ),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "SeshatCore",
            path: "Sources/SeshatCore"
        ),
        .target(
            name: "SeshatAudio",
            dependencies: [
                "SeshatCore",
            ],
            path: "Sources/SeshatAudio"
        ),
        .target(
            name: "SeshatTranscription",
            dependencies: [
                "SeshatCore",
            ],
            path: "Sources/SeshatTranscription"
        ),
        .target(
            name: "SeshatSession",
            dependencies: [
                "SeshatCore",
                "SeshatAudio",
                "SeshatTranscription",
            ],
            path: "Sources/SeshatSession"
        ),
        .target(
            name: "SeshatTestSupport",
            dependencies: [
                "SeshatCore",
            ],
            path: "Sources/SeshatTestSupport"
        ),
        .executableTarget(
            name: "SeshatAppKit",
            dependencies: [
                "SeshatCore",
                "SeshatSession",
                "SeshatAudio",
                "SeshatTranscription",
            ],
            path: "Sources/SeshatAppKit"
        ),
        .testTarget(
            name: "SeshatCoreTests",
            dependencies: [
                "SeshatCore",
            ],
            path: "Tests/SeshatCoreTests"
        ),
        .testTarget(
            name: "SeshatAudioTests",
            dependencies: [
                "SeshatAudio",
                "SeshatTestSupport",
            ],
            path: "Tests/SeshatAudioTests"
        ),
        .testTarget(
            name: "SeshatTranscriptionTests",
            dependencies: [
                "SeshatTranscription",
                "SeshatTestSupport",
            ],
            path: "Tests/SeshatTranscriptionTests"
        ),
        .testTarget(
            name: "SeshatSessionTests",
            dependencies: [
                "SeshatSession",
                "SeshatTestSupport",
            ],
            path: "Tests/SeshatSessionTests"
        ),
        .testTarget(
            name: "SeshatAppKitTests",
            dependencies: [
                "SeshatAppKit",
                "SeshatTestSupport",
            ],
            path: "Tests/SeshatAppKitTests"
        ),
    ]
)
```

- Create `Package.swift` exactly as above.
- Do not add Plan 00 symbols.
- Do not add FluidAudio placeholders yet.
- Do not add `swiftLanguageModes` yet.

Verification:

```bash
swift package dump-package
rg -n '"PS(Core|Audio|Transcription|Session|TestSupport|AppKit)(Tests)?"' Package.swift
```

Commit:

```bash
git add Package.swift
git commit -m "plan-01 step 2: declare interim swift package target graph"
```

### Step 3. Create production source scaffolding in small commits

**Time rule**: every substep below is 2–5 minutes.
**Import-boundary rule**: non-`Composition/` `SeshatAppKit` placeholders must not import `SeshatAudio` or `SeshatTranscription`. Allowed imports are `Foundation`, `AppKit`, `SwiftUI`, `SeshatCore`, `SeshatSession`.

Boundary verification command:

```bash
grep -r "import SeshatAudio\\|import SeshatTranscription" Sources/SeshatAppKit/ | grep -v Composition/
```

Expected result: no output.

| Substep | Files | Placeholder content | Verification | Commit |
|---|---|---|---|---|
| `3.1` | `Sources/SeshatCore/SeshatCoreModule.swift`, `Tests/SeshatCoreTests/SeshatCoreModuleCompileTests.swift` | `public enum SeshatCoreModule {}` plus trivial compile-witness XCTest | `swift test --filter SeshatCoreModuleCompileTests` | `git commit -m "plan-01 step 3.1: scaffold pscore placeholder"` |
| `3.2` | `Sources/SeshatAudio/SeshatAudioModule.swift`, `Tests/SeshatAudioTests/SeshatAudioModuleCompileTests.swift` | `public enum SeshatAudioModule {}` plus trivial compile-witness XCTest | `swift test --filter SeshatAudioModuleCompileTests` | `git commit -m "plan-01 step 3.2: scaffold psaudio placeholder"` |
| `3.3` | `Sources/SeshatTranscription/SeshatTranscriptionModule.swift`, `Tests/SeshatTranscriptionTests/SeshatTranscriptionModuleCompileTests.swift` | `public enum SeshatTranscriptionModule {}` plus trivial compile-witness XCTest | `swift test --filter SeshatTranscriptionModuleCompileTests` | `git commit -m "plan-01 step 3.3: scaffold pstranscription placeholder"` |
| `3.4` | `Sources/SeshatSession/SeshatSessionModule.swift`, `Tests/SeshatSessionTests/SeshatSessionModuleCompileTests.swift` | `public enum SeshatSessionModule {}` plus trivial compile-witness XCTest | `swift test --filter SeshatSessionModuleCompileTests` | `git commit -m "plan-01 step 3.4: scaffold pssession placeholder"` |
| `3.5` | `Sources/SeshatTestSupport/SeshatTestSupportModule.swift`, `Tests/SeshatAudioTests/SeshatTestSupportModuleCompileTests.swift` | `public enum SeshatTestSupportModule {}` plus trivial compile-witness XCTest | `swift test --filter SeshatTestSupportModuleCompileTests` | `git commit -m "plan-01 step 3.5: scaffold pstestsupport placeholder"` |
| `3.6` | `Sources/SeshatAppKit/Permissions/SeshatAppKitPermissionsModule.swift`, `Tests/SeshatAppKitTests/SeshatAppKitPermissionsCompileTests.swift` | `public enum SeshatAppKitPermissionsModule {}` plus trivial compile-witness XCTest | `swift test --filter SeshatAppKitPermissionsCompileTests` and the boundary grep above | `git commit -m "plan-01 step 3.6: scaffold psappkit permissions placeholder"` |
| `3.7` | `Sources/SeshatAppKit/SeshatApp.swift`, `Sources/SeshatAppKit/AppDelegate.swift`, `Tests/SeshatAppKitTests/SeshatAppKitShellCompileTests.swift` | inert `public enum SeshatAppPlaceholder {}` + inert `public enum AppDelegatePlaceholder {}` (NO `@main`, NO `App` conformance) + trivial compile-witness XCTest. Plan 04 Step 10 overwrites `SeshatApp.swift` with the real injectable shell; Plan 99 adds the first `@main`. | `swift test --filter SeshatAppKitShellCompileTests`, the boundary grep above, AND `grep -r "@main" Sources/SeshatAppKit/` must print nothing | `git commit -m "plan-01 step 3.7: scaffold psappkit placeholder (no @main)"` |
| `3.8` | `Sources/SeshatAppKit/Composition/.gitkeep`, `Tests/SeshatAppKitTests/CompositionDirectoryLayoutTests.swift` | empty directory only; no `AppComposition.swift`; inert layout witness test | `test -f Sources/SeshatAppKit/Composition/.gitkeep`, `test ! -f Sources/SeshatAppKit/Composition/AppComposition.swift`, `swift test --filter CompositionDirectoryLayoutTests` | `git commit -m "plan-01 step 3.8: scaffold empty composition directory"` |

### Step 4. Add one placeholder XCTest per declared test target

**Time rule**: every substep below is 2–5 minutes.
**Rule**: each file adds one `XCTAssertTrue(true)` test and nothing else.

| Substep | File | Verification | Commit |
|---|---|---|---|
| `4.1` | `Tests/SeshatCoreTests/SeshatCorePlaceholderTests.swift` | `swift test --filter SeshatCoreTests` | `git commit -m "plan-01 step 4.1: add pscore placeholder test"` |
| `4.2` | `Tests/SeshatAudioTests/SeshatAudioPlaceholderTests.swift` | `swift test --filter SeshatAudioTests` | `git commit -m "plan-01 step 4.2: add psaudio placeholder test"` |
| `4.3` | `Tests/SeshatTranscriptionTests/SeshatTranscriptionPlaceholderTests.swift` | `swift test --filter SeshatTranscriptionTests` | `git commit -m "plan-01 step 4.3: add pstranscription placeholder test"` |
| `4.4` | `Tests/SeshatSessionTests/SeshatSessionPlaceholderTests.swift` | `swift test --filter SeshatSessionTests` | `git commit -m "plan-01 step 4.4: add pssession placeholder test"` |
| `4.5` | `Tests/SeshatAppKitTests/SeshatAppKitPlaceholderTests.swift` | `swift test --filter SeshatAppKitTests` | `git commit -m "plan-01 step 4.5: add psappkit placeholder test"` |

### Step 5. Amend the manifest to final form

**Time**: 3–5 minutes.
**Files**: `Package.swift`.
**Rule**: Step 5 is the only step that introduces the Step 5-only manifest changes.

Required changes:

- add `swiftLanguageModes: [.v6]`
- add the commented FluidAudio package placeholder
- add the commented FluidAudio product placeholder under `SeshatTranscription`

Verification:

```bash
rg -n 'TODO\\(plan-03\\).*FluidAudio' Package.swift
rg -n 'swiftLanguageModes:[[:space:]]*\\[[[:space:]]*\\.v6' Package.swift
swift package dump-package
```

Commit:

```bash
git add Package.swift
git commit -m "plan-01 step 5: finalize manifest for swift 6 and future fluidaudio pin"
```

### Step 6. Add `README.md` stub

**Time**: 2–4 minutes.
**Files**: `README.md`.

- Write `# Seshat`.
- Include `macOS 14+`, `Apple Silicon`, `swift build`, and `swift test`.
- Include a license line or explicit placeholder.
- Do not add marketing copy.

Verification:

```bash
test -f README.md
rg -n '^# Seshat$|macOS 14\\+|Apple Silicon|swift build|swift test' README.md
```

Commit:

```bash
git add README.md
git commit -m "plan-01 step 6: add readme stub"
```

### Step 7. Build verification gate

**Time**: 2–5 minutes.
**Rule**: run `swift build`; expected exit `0`. If it fails, earlier steps are broken; fix them instead of redefining Step 7.

```bash
swift build
git commit --allow-empty -m "plan-01 step 7: verify build gate"
```

### Step 8. Test verification gate

**Time**: 2–5 minutes.
**Rule**: run `swift test`; expected exit `0`. If it fails, earlier steps are broken; fix them instead of redefining Step 8.

```bash
swift test
git commit --allow-empty -m "plan-01 step 8: verify test gate"
```

### Step 9. Final completion check

**Time**: 2–4 minutes.
**Rule**: if Steps 7–8 required real fixes, stage them now; otherwise use an empty completion commit.

Verification:

```bash
git status --short
git log --oneline -n 5
```

Commit:

```bash
git add .
git commit --allow-empty -m "plan-01 step 9: finalize spm scaffold"
```

## D. Dependency Table

| Group | Steps | Can Parallelize | Notes |
|---|---|---|---|
| 1 | `1` | No | git first |
| 2 | `2`, `6` | Yes after `1` | manifest and README are independent |
| 3 | `3.1`–`3.5` | Yes after `2` | library placeholders are independent |
| 4 | `3.6`–`3.8` | Serial | one owner for `Sources/SeshatAppKit/**` |
| 5 | `4.1`–`4.5` | Mostly yes | one owner per test target |
| 6 | `5` | No | one owner for `Package.swift` |
| 7 | `7`, `8` | Serial | build before full test sweep |
| 8 | `9` | No | close out only after gates pass |

## E. Handoff Signals

After Plan 01 completes, downstream plans may assume:

- the repo is initialized and `.gitignore` exists
- the manifest declares exactly six production targets and five test targets
- the manifest matches the Step 5 final shape
- `SeshatAudio -> SeshatCore`
- `SeshatTranscription -> SeshatCore`, with FluidAudio deferred but reserved in comments
- `SeshatSession -> SeshatCore + SeshatAudio + SeshatTranscription`
- `SeshatAppKit -> SeshatCore + SeshatSession + SeshatAudio + SeshatTranscription`
- `Sources/SeshatAppKit/Composition/` exists and `AppComposition.swift` does not
- non-`Composition/` `SeshatAppKit` placeholders do not import `SeshatAudio` or `SeshatTranscription`
- `swift build` and `swift test` both pass

## F. Forbidden Duplicates Semantic Audit

Every `public` or `internal` declaration created by Plan 01 is listed below. Anything that looks like a real Week 1 API instead of inert scaffolding should be deleted from this plan.

| Symbol | Kind | Plan 00 concept it could duplicate | Why it is not a duplicate |
|---|---|---|---|
| `SeshatCore` | manifest module/product | `SeshatCore` target | required target identity, not a second concept |
| `SeshatAudio` | manifest module/product | `SeshatAudio` target | required target identity, not a second concept |
| `SeshatTranscription` | manifest module/product | `SeshatTranscription` target | required target identity, not a second concept |
| `SeshatSession` | manifest module/product | `SeshatSession` target | required target identity, not a second concept |
| `SeshatTestSupport` | manifest module/product | `SeshatTestSupport` target | required target identity, not a second concept |
| `SeshatAppKit` | manifest executable/module | `SeshatAppKit` target | required target identity, not a second concept |
| `SeshatCoreTests` | manifest test target | N/A — pure scaffolding | target container only |
| `SeshatAudioTests` | manifest test target | N/A — pure scaffolding | target container only |
| `SeshatTranscriptionTests` | manifest test target | N/A — pure scaffolding | target container only |
| `SeshatSessionTests` | manifest test target | N/A — pure scaffolding | target container only |
| `SeshatAppKitTests` | manifest test target | N/A — pure scaffolding | target container only |
| `SeshatCoreModule` | `public enum` namespace | `PCMBuffer`, `SeshatError`, `SeshatConfig`, `SeshatLogger` | inert namespace only; no shared contract shape |
| `SeshatAudioModule` | `public enum` namespace | `AVAudioCaptureService`, `AudioResampler`, `AudioCapturing` | inert namespace only; no production audio behavior |
| `SeshatTranscriptionModule` | `public enum` namespace | `FluidAudioTranscriber`, `Transcribing`, `ModelDownloadProgress` | inert namespace only; no production transcription behavior |
| `SeshatSessionModule` | `public enum` namespace | `SessionCoordinator`, `SessionState` | inert namespace only; no second session abstraction |
| `SeshatTestSupportModule` | `public enum` namespace | `FakeAudioCapturing`, `FakeTranscriber` | inert namespace only; no second fake surface |
| `SeshatAppKitPermissionsModule` | `public enum` namespace | `MicrophonePermissionRequesting`, `AppKitMicrophonePermissionRequester` | inert namespace only; no permission contract |
| `SeshatAppPlaceholder` | `public enum` namespace | Plan 04 `SeshatApp` shell | inert namespace only; Plan 01 does NOT scaffold `@main` or `App` conformance — Plan 04 writes the real shell, Plan 99 ships the `@main` entry point |
| `AppDelegatePlaceholder` | `public enum` namespace | Plan 04 `AppDelegate` | inert namespace only; Plan 04 v2 currently removes `AppDelegate`, so this is purely a compile placeholder |
| `SeshatCoreModuleCompileTests` | `internal final class` XCTestCase | N/A — pure scaffolding | compile witness only |
| `SeshatAudioModuleCompileTests` | `internal final class` XCTestCase | N/A — pure scaffolding | compile witness only |
| `SeshatTranscriptionModuleCompileTests` | `internal final class` XCTestCase | N/A — pure scaffolding | compile witness only |
| `SeshatSessionModuleCompileTests` | `internal final class` XCTestCase | N/A — pure scaffolding | compile witness only |
| `SeshatTestSupportModuleCompileTests` | `internal final class` XCTestCase | N/A — pure scaffolding | compile witness only |
| `SeshatAppKitPermissionsCompileTests` | `internal final class` XCTestCase | N/A — pure scaffolding | compile witness only |
| `SeshatAppKitShellCompileTests` | `internal final class` XCTestCase | N/A — pure scaffolding | compile witness only |
| `CompositionDirectoryLayoutTests` | `internal final class` XCTestCase | `AppComposition` | layout witness only; no composition root symbol created |
| `SeshatCorePlaceholderTests` | `internal final class` XCTestCase | N/A — pure scaffolding | one-line no-op test only |
| `SeshatAudioPlaceholderTests` | `internal final class` XCTestCase | N/A — pure scaffolding | one-line no-op test only |
| `SeshatTranscriptionPlaceholderTests` | `internal final class` XCTestCase | N/A — pure scaffolding | one-line no-op test only |
| `SeshatSessionPlaceholderTests` | `internal final class` XCTestCase | N/A — pure scaffolding | one-line no-op test only |
| `SeshatAppKitPlaceholderTests` | `internal final class` XCTestCase | N/A — pure scaffolding | one-line no-op test only |

Audit conclusion:

- No Plan 00 Section C symbol is redefined.
- No new public or internal protocol abstracts a Plan 00 concept under another name.
- No logging wrapper is introduced.
- No second composition root is introduced.

## G. Sibling Cross-Plan Audit

### Plan 02

- Declared expectation: `SeshatAudio` depends on `SeshatCore`.
- Manifest check: both Step 2 and Step 5 manifests declare `SeshatAudio` with dependency `["SeshatCore"]`.
- Result: satisfied.

### Plan 03

- Declared expectation: `SeshatTranscription` depends on `SeshatCore` plus FluidAudio, but the FluidAudio product is deferred until Plan 03 verifies the pin.
- Manifest check: Step 2 declares `SeshatTranscription -> SeshatCore`; Step 5 adds the exact commented TODO placeholders for the future package and product.
- Result: satisfied. No mismatch.

### Plan 04

- Declared expectation: `SeshatAppKit` executable depends on `SeshatCore`, `SeshatSession`, `SeshatAudio`, `SeshatTranscription`.
- Manifest check: both manifest phases use that exact dependency set.
- Layering check: Step 3 repeats the non-`Composition/` import restriction that Plan 04 also depends on.
- `@main` check (v2.1): Plan 04 v2 forbids `@main` in `Sources/SeshatAppKit/` (lines 875, 1030, 1037). Plan 01 v2.1 Step 3.7 scaffolds only inert placeholder namespaces — NO `@main`, NO `App` conformance. Plan 04 Step 10 overwrites the placeholder file with the real injectable shell (still no `@main`). Plan 99 is the first plan that ships `@main`.
- Result: satisfied.

### Plan 99

- Declared expectation: `Sources/SeshatAppKit/Composition/` exists but is empty except for scaffold material; `AppComposition.swift` is not created yet.
- Scaffold check: Step `3.8` creates `.gitkeep` only and explicitly checks that `AppComposition.swift` does not exist.
- Result: satisfied.

### Cross-plan summary

- No sibling cross-plan mismatch was found.

## H. Self-verification Checklist

- [x] No Plan 00 Section C symbol redefined
- [x] No new public/internal protocol abstracts a Plan 00 concept under a different name
- [x] No logging wrapper other than reference to `SeshatLogger` (Plan 01 adds none)
- [x] `Sources/SeshatAppKit/Composition/AppComposition.swift` is NOT created
- [x] No `import SeshatAudio` / `import SeshatTranscription` in non-Composition `SeshatAppKit` files
- [x] Each step is 2–5 minutes of focused work
- [x] Each step has a concrete verification command
- [x] Sibling target-dependency expectations are satisfied

## I. Definition Of Done

- `git init` ran
- `.gitignore` exists
- interim `Package.swift` landed in Step 2
- final `Package.swift` landed in Step 5
- Step 3 has 8 substeps, each with its own verification and commit
- Step 4 has 5 substeps, each with its own verification and commit
- `README.md` exists and is non-marketing
- `swift build` passes
- `swift test` passes
- `Sources/SeshatAppKit/Composition/` exists and `AppComposition.swift` does not
- the working tree is clean after completion

## Changes in v2.2 (post-execution fix)

- Step 3.7 now ALSO creates `Sources/SeshatAppKit/main.swift` containing `import Foundation; exit(0)` as a placeholder entry point. Without this, `swift build` fails to link the executable target because `SeshatAppKit` is declared `.executableTarget()` in `Package.swift` but no file provides an entry point. The placeholder is a `main.swift` (SPM special file), NOT the `@main` attribute - these are different SPM conventions. The 'no `@main` in Sources' rule remains intact.
- Plan 99 v2.1 obligation: before creating `Sources/SeshatAppKit/Composition/SeshatAppMain.swift`, DELETE `Sources/SeshatAppKit/main.swift` (the placeholder). Otherwise SPM will see two entry points and refuse to link.
- This amendment was found during Plan 01 execution attempt on 2026-04-17. Root cause: SPM requires executable targets to have a link-time entry point regardless of Plan 99's later rewrite.
