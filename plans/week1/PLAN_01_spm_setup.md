# Plan 01: SPM Project Setup
**Goal**: Create a buildable Swift Package with the 6 targets + 5 test targets defined in Plan 00 Section B, plus git init and README stub. Nothing else.
**Architecture**: Swift 6 package manifest, macOS 14+, executable composition-root target + 4 libraries + shared test-support library.
**Tech Stack**: Swift 6.0 manifest syntax, SPM, XCTest, git.
**Depends on**: nothing (this is Week 1's foundation step).
**Plan 00 contract read**: Section B (target graph + directory layout), Section G (Plan 01 consumable list).

## A. Prerequisites
- macOS 14+ on Apple Silicon.
- Xcode / CLT installed and selected.
- `swift --version` reports 5.9 or newer.
- `git` is available on `PATH`.
- Work at repo root: `/Users/nitinkum/Projects/nitkrar/whisper_flow`.

Use `// swift-tools-version: 6.0`.

Why this concrete choice:
- It satisfies the `5.9+` requirement.
- It supports `swiftLanguageModes: [.v6]` directly.
- The local toolchain is already Swift 6.x.
- It avoids mixing a 5.9/5.10 manifest with experimental strict-concurrency flags.

## Reference Artifacts

### Final `Package.swift`
```swift
// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "PersonalScribe",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "PSCore",
            targets: ["PSCore"]
        ),
        .library(
            name: "PSAudio",
            targets: ["PSAudio"]
        ),
        .library(
            name: "PSTranscription",
            targets: ["PSTranscription"]
        ),
        .library(
            name: "PSSession",
            targets: ["PSSession"]
        ),
        .library(
            name: "PSTestSupport",
            targets: ["PSTestSupport"]
        ),
        .executable(
            name: "PSAppKit",
            targets: ["PSAppKit"]
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
            name: "PSCore",
            path: "Sources/PSCore"
        ),
        .target(
            name: "PSAudio",
            dependencies: [
                "PSCore",
            ],
            path: "Sources/PSAudio"
        ),
        .target(
            name: "PSTranscription",
            dependencies: [
                "PSCore",
                // TODO(plan-03): After pinning FluidAudio above, add:
                // .product(name: "<verified-product-name>", package: "<verified-package-name>"),
            ],
            path: "Sources/PSTranscription"
        ),
        .target(
            name: "PSSession",
            dependencies: [
                "PSCore",
                "PSAudio",
                "PSTranscription",
            ],
            path: "Sources/PSSession"
        ),
        .target(
            name: "PSTestSupport",
            dependencies: [
                "PSCore",
            ],
            path: "Sources/PSTestSupport"
        ),
        .executableTarget(
            name: "PSAppKit",
            dependencies: [
                "PSCore",
                "PSAudio",
                "PSTranscription",
                "PSSession",
            ],
            path: "Sources/PSAppKit"
        ),
        .testTarget(
            name: "PSCoreTests",
            dependencies: [
                "PSCore",
            ],
            path: "Tests/PSCoreTests"
        ),
        .testTarget(
            name: "PSAudioTests",
            dependencies: [
                "PSAudio",
                "PSTestSupport",
            ],
            path: "Tests/PSAudioTests"
        ),
        .testTarget(
            name: "PSTranscriptionTests",
            dependencies: [
                "PSTranscription",
                "PSTestSupport",
            ],
            path: "Tests/PSTranscriptionTests"
        ),
        .testTarget(
            name: "PSSessionTests",
            dependencies: [
                "PSSession",
                "PSTestSupport",
            ],
            path: "Tests/PSSessionTests"
        ),
        .testTarget(
            name: "PSAppKitTests",
            dependencies: [
                "PSAppKit",
                "PSTestSupport",
            ],
            path: "Tests/PSAppKitTests"
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

## B. Task Breakdown

### Step 1. `git init` + `.gitignore` + initial commit
**Files**: `.gitignore`, `.git/`
**Write-failing-test / verification**: use repo-state checks instead of XCTest.
**Run-fails**
```bash
git rev-parse --is-inside-work-tree
test -f .gitignore
```
**Implement**
- Run `git init`.
- Add root `.gitignore` exactly as above.
- Stage only `.gitignore` for the first commit.
**Run-passes**
```bash
git rev-parse --is-inside-work-tree
git status --short
```
**Commit**
```bash
git add .gitignore
git commit -m "plan-01 step 1: initialize repository scaffolding"
```

### Step 2. Add `Package.swift` with the exact target graph
**Files**: `Package.swift`
**Write-failing-test / verification**: manifest validation before any sources exist.
**Run-fails**
```bash
swift package dump-package
```
**Implement**
- Create `Package.swift`.
- Declare the 6 production targets and 5 test targets from Plan 00 Section G.
- Match the Section B graph exactly.
- Set `.macOS(.v14)`.
- Do not add live FluidAudio dependency lines yet.
- Do not add any Plan 00 Section C symbol.
**Run-passes**
```bash
swift package dump-package
rg -n '"PS(Core|Audio|Transcription|Session|TestSupport|AppKit)(Tests)?"' Package.swift
```
**Commit**
```bash
git add Package.swift
git commit -m "plan-01 step 2: declare swift package target graph"
```

### Step 3. Create placeholder production source layout
**Files**
- `Sources/PSCore/PSCoreModule.swift`
- `Sources/PSAudio/PSAudioModule.swift`
- `Sources/PSTranscription/PSTranscriptionModule.swift`
- `Sources/PSSession/PSSessionModule.swift`
- `Sources/PSTestSupport/PSTestSupportModule.swift`
- `Sources/PSAppKit/PersonalScribeApp.swift`
- `Sources/PSAppKit/AppDelegate.swift`
- `Sources/PSAppKit/Permissions/PSAppKitPermissionsModule.swift`
- `Sources/PSAppKit/Composition/.gitkeep`
**Write-failing-test / verification**: `swift build` should fail after Step 2 because target paths are still empty/incomplete.
**Run-fails**
```bash
swift build
```
**Implement**
- Create each target directory from the manifest.
- Library targets get only `// placeholder` or empty target-namespace files such as `public enum PSCoreModule {}`.
- Create `Sources/PSAppKit/Composition/` but do not create `AppComposition.swift`.
- Do not create production `PSAudio` or `PSTranscription` files like `AVAudioCaptureService.swift`, `AudioResampler.swift`, or `FluidAudioTranscriber.swift`.
- For `PSAppKit`, add the thinnest temporary entry point required to let the executable target link. It must stay non-contractual and disposable.
**Run-passes**
```bash
swift build
```
**Commit**
```bash
git add Sources
git commit -m "plan-01 step 3: add placeholder production target sources"
```

### Step 4. Add one placeholder XCTest per test target
**Files**
- `Tests/PSCoreTests/PSCorePlaceholderTests.swift`
- `Tests/PSAudioTests/PSAudioPlaceholderTests.swift`
- `Tests/PSTranscriptionTests/PSTranscriptionPlaceholderTests.swift`
- `Tests/PSSessionTests/PSSessionPlaceholderTests.swift`
- `Tests/PSAppKitTests/PSAppKitPlaceholderTests.swift`
**Write-failing-test / verification**: filtered test invocations should fail before the files exist.
**Run-fails**
```bash
swift test --filter PSCorePlaceholderTests/testPlaceholder
swift test --filter PSAudioPlaceholderTests/testPlaceholder
swift test --filter PSTranscriptionPlaceholderTests/testPlaceholder
swift test --filter PSSessionPlaceholderTests/testPlaceholder
swift test --filter PSAppKitPlaceholderTests/testPlaceholder
```
**Implement**
- Create one XCTest file per test target.
- Each file contains exactly one `XCTAssertTrue(true)` test.
- Keep imports minimal.
- Do not add behavior tests for Plan 00 contracts yet.
**Run-passes**
```bash
swift test --filter PSCorePlaceholderTests/testPlaceholder
swift test --filter PSAudioPlaceholderTests/testPlaceholder
swift test --filter PSTranscriptionPlaceholderTests/testPlaceholder
swift test --filter PSSessionPlaceholderTests/testPlaceholder
swift test --filter PSAppKitPlaceholderTests/testPlaceholder
```
**Commit**
```bash
git add Tests
git commit -m "plan-01 step 4: add placeholder module tests"
```

### Step 5. Turn on Swift 6 mode and add the commented FluidAudio placeholder
**Files**: `Package.swift`
**Write-failing-test / verification**: grep for missing final manifest lines.
**Run-fails**
```bash
rg -n 'swiftLanguageModes:[[:space:]]*\\[[[:space:]]*\\.v6' Package.swift
rg -n 'TODO\\(plan-03\\).*FluidAudio' Package.swift
```
**Implement**
- Add `swiftLanguageModes: [.v6]`.
- Keep tools version at `6.0`.
- Add the commented package dependency placeholder for FluidAudio.
- Add the commented product placeholder in `PSTranscription` dependencies.
- Do not pin or guess URL, product, package identity, or version.
**Run-passes**
```bash
rg -n 'swiftLanguageModes:[[:space:]]*\\[[[:space:]]*\\.v6' Package.swift
rg -n 'TODO\\(plan-03\\).*FluidAudio' Package.swift
swift build
```
**Commit**
```bash
git add Package.swift
git commit -m "plan-01 step 5: configure swift 6 mode and transcriber dependency placeholder"
```

### Step 6. Add `README.md` stub
**Files**: `README.md`
**Write-failing-test / verification**: file-presence and content checks.
**Run-fails**
```bash
test -f README.md
rg -n '^# PersonalScribe$|macOS 14\\+|Apple Silicon|swift build|swift test' README.md
```
**Implement**
- Write project name.
- Include license line or explicit license placeholder.
- Include minimum system requirements: macOS 14+, Apple Silicon.
- Include build instructions: `swift build`, `swift test`.
- Do not add marketing copy.
**Run-passes**
```bash
test -f README.md
rg -n '^# PersonalScribe$|macOS 14\\+|Apple Silicon|swift build|swift test' README.md
```
**Commit**
```bash
git add README.md
git commit -m "plan-01 step 6: add readme stub"
```

### Step 7. Final build gate
**Files**: no new files
**Write-failing-test / verification**: `swift build` is the gate.
**Run-fails**
```bash
swift build
```
**Implement**
- Fix only scaffold-level issues exposed by the build.
- Do not implement real Plan 00 shared types to satisfy the compiler.
**Run-passes**
```bash
swift build
```
**Commit**
```bash
git add Package.swift Sources
git commit -m "plan-01 step 7: verify package build"
```

### Step 8. Final test gate
**Files**: no new files
**Write-failing-test / verification**: `swift test` is the gate.
**Run-fails**
```bash
swift test
```
**Implement**
- Fix only scaffold wiring or test-target issues.
- Do not start implementing shared contracts.
**Run-passes**
```bash
swift test
```
**Commit**
```bash
git add Package.swift Sources Tests
git commit -m "plan-01 step 8: verify package tests"
```

### Step 9. Final Plan 01 completion commit
**Files**: all changed files from Steps 7-8 if any
**Write-failing-test / verification**: repo cleanliness and recent history.
**Run-fails**
```bash
git status --short
git log --oneline -n 3
```
**Implement**
- If Steps 7-8 required fixes not yet committed, stage them now.
- Create the completion commit.
- Leave a clean tree.
**Run-passes**
```bash
git status --short
git log --oneline -n 5
```
**Commit**
```bash
git add .
git commit -m "plan-01 step 9: finalize spm scaffold"
```

## C. Dependency Table

| Group | Steps | Can Parallelize | Notes |
|---|---|---|---|
| 1 | 1 | No | Establish repo baseline first. |
| 2 | 2, 6 | Yes, after 1 | Manifest and README are independent. |
| 3 | 3, 4 | Yes, after 2 | Source placeholders and test placeholders can be split. |
| 4 | 5 | No | Manifest hardening should happen after target layout is real. |
| 5 | 7, 8 | Serial | Build first, then test. |
| 6 | 9 | No | Final commit only after verification passes. |

Suggested worker split:
- Worker A: `Package.swift` in Steps 2 and 5.
- Worker B: `Sources/` placeholders in Step 3.
- Worker C: `Tests/` placeholders in Step 4.
- One owner only for `Package.swift`.
- No worker creates `AppComposition.swift`.

## D. Handoff Signals

After Plan 01 completes, downstream plans may assume:
- A git repo exists at repo root with Plan 01 scaffold commits.
- Root `.gitignore` exists for standard Swift/SPM/Xcode/macOS noise.
- Root `Package.swift` declares exactly these production targets: `PSCore`, `PSAudio`, `PSTranscription`, `PSSession`, `PSTestSupport`, `PSAppKit`.
- Root `Package.swift` declares exactly these test targets: `PSCoreTests`, `PSAudioTests`, `PSTranscriptionTests`, `PSSessionTests`, `PSAppKitTests`.
- The dependency graph matches Plan 00 Section B exactly.
- The deployment target is `.macOS(.v14)`.
- Swift 6 language mode is declared via `swiftLanguageModes: [.v6]`.
- `PSTranscription` contains only a commented FluidAudio placeholder; nothing is pinned yet.
- The `Sources/` tree exists for all six production targets.
- `Sources/PSAppKit/Composition/` exists, but `Sources/PSAppKit/Composition/AppComposition.swift` does not.
- Placeholder production files are disposable and may be overwritten by later plans.
- `Tests/` contains one trivially passing placeholder XCTest per declared test target.
- `README.md` exists with minimum requirements and build instructions.
- `swift build` passes.
- `swift test` passes.

Plan-specific assumptions:
- Plan 00 may overwrite placeholders with real shared contracts without changing target names or paths.
- Plan 02 may add production files under `Sources/PSAudio/` without changing the package graph.
- Plan 03 may replace the FluidAudio comments with a verified pinned dependency and real transcriber implementation.
- Plan 04 may implement `PSAppKit/Permissions/AppKitMicrophonePermissionRequester.swift` and UI bootstrap, but still must not create `AppComposition.swift`.
- Plan 99 may create `Sources/PSAppKit/Composition/AppComposition.swift` after Plans 02, 03, and 04 land.

Implementation guardrails:
- Do not define `PCMBuffer`, `SessionState`, `PSError`, `PSConfig`, `PSLogger`, `AudioCapturing`, `Transcribing`, `SessionCoordinator`, `AppComposition`, or any other Plan 00 Section C symbol.
- Do not create production `PSAudio` or `PSTranscription` source files in Plan 01.
- Do not guess the FluidAudio URL, package identity, product name, or version.
- Do not use `sl` or `jf`; use `git`.

Definition of done:
- `git init` ran.
- `.gitignore` exists.
- Initial scaffold commit exists.
- `Package.swift` matches the six-target / five-test-target contract.
- Placeholder source files compile.
- Placeholder tests pass.
- `README.md` exists and is non-marketing.
- `swift build` succeeds.
- `swift test` succeeds.
- Final completion commit exists.
- Working tree is clean.
