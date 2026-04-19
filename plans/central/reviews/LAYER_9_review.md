# Layer 9 Review

Verdict: NEEDS REVISION

Finding summary: blocker 0, major 2, minor 1, nit 0.

## Manus extension gap

- `tagline` is an extension needed at Stage 1. The plan's Stage 1 surface is still limited to the locked prompt fields at `plans/central/LAYER_9_app_brand.md:45-46,56,76,243-245`, while Manus declares `tagline` at `/tmp/manus-rename-bundle/Ninimma_UI_Bundle/swift/AppBrand.swift:29-30`.
- `pronunciation` is an extension needed at Stage 1. The current plan omits it at `plans/central/LAYER_9_app_brand.md:45-46,56,76,243-245`, while Manus declares it at `/tmp/manus-rename-bundle/Ninimma_UI_Bundle/swift/AppBrand.swift:32-33`.
- `shortDescription` is an extension needed at Stage 1. The plan omits it at `plans/central/LAYER_9_app_brand.md:45-46,56,76,243-245`, while Manus declares it at `/tmp/manus-rename-bundle/Ninimma_UI_Bundle/swift/AppBrand.swift:35-36`.
- `About.heading` is an extension needed at Stage 1. The plan omits any `About` namespace at `plans/central/LAYER_9_app_brand.md:45-46,56,76,243-245`, while Manus declares it at `/tmp/manus-rename-bundle/Ninimma_UI_Bundle/swift/AppBrand.swift:49-52`.
- `About.subheading` is an extension needed at Stage 1. The plan omits any `About` namespace at `plans/central/LAYER_9_app_brand.md:45-46,56,76,243-245`, while Manus declares it at `/tmp/manus-rename-bundle/Ninimma_UI_Bundle/swift/AppBrand.swift:53-55`.
- `About.bodyCopy` is an extension needed at Stage 1. The plan omits any `About` namespace at `plans/central/LAYER_9_app_brand.md:45-46,56,76,243-245`, while Manus declares it at `/tmp/manus-rename-bundle/Ninimma_UI_Bundle/swift/AppBrand.swift:57-65`.
- `About.tagline` is an extension needed at Stage 1. The plan omits any `About` namespace at `plans/central/LAYER_9_app_brand.md:45-46,56,76,243-245`, while Manus declares it at `/tmp/manus-rename-bundle/Ninimma_UI_Bundle/swift/AppBrand.swift:67-68`.
- `Assets.appIcon` is an extension needed at Stage 1. The plan omits any `Assets` namespace at `plans/central/LAYER_9_app_brand.md:45-46,56,76,243-245`, while Manus declares it at `/tmp/manus-rename-bundle/Ninimma_UI_Bundle/swift/AppBrand.swift:76-79`.
- `Assets.wordmark` is an extension needed at Stage 1. The plan omits any `Assets` namespace at `plans/central/LAYER_9_app_brand.md:45-46,56,76,243-245`, while Manus declares it at `/tmp/manus-rename-bundle/Ninimma_UI_Bundle/swift/AppBrand.swift:80-81`.
- `Assets.lockupHorizontal` is an extension needed at Stage 1. The plan omits any `Assets` namespace at `plans/central/LAYER_9_app_brand.md:45-46,56,76,243-245`, while Manus declares it at `/tmp/manus-rename-bundle/Ninimma_UI_Bundle/swift/AppBrand.swift:83-85`.
- `Assets.lockupStacked` is an extension needed at Stage 1. The plan omits any `Assets` namespace at `plans/central/LAYER_9_app_brand.md:45-46,56,76,243-245`, while Manus declares it at `/tmp/manus-rename-bundle/Ninimma_UI_Bundle/swift/AppBrand.swift:86-87`.
- `Assets.statusBarIdle` is an extension needed at Stage 1. The plan omits any `Assets` namespace at `plans/central/LAYER_9_app_brand.md:45-46,56,76,243-245`, while Manus declares it at `/tmp/manus-rename-bundle/Ninimma_UI_Bundle/swift/AppBrand.swift:89-90`.
- `Assets.statusBarListening` is an extension needed at Stage 1. The plan omits any `Assets` namespace at `plans/central/LAYER_9_app_brand.md:45-46,56,76,243-245`, while Manus declares it at `/tmp/manus-rename-bundle/Ninimma_UI_Bundle/swift/AppBrand.swift:92-93`.

## Findings by checklist item

1. PASS — The do-not-diverge paragraph is present verbatim at the top of the plan under `## Critical discipline` in `plans/central/LAYER_9_app_brand.md:3-5`, matching `plans/CENTRAL_LAYERS_PROMPT.md:13-17`.

2. PASS — The locked Layer 9 decisions are carried forward correctly: `AppBrand` is a namespace-only enum in `SeshatCore`, and the plan explicitly assigns `displayName`, `bundleIdentifier`, `logSubsystem`, `websiteURL`, `privacyURL`, `termsURL`, `version`, and `buildNumber` to it at `plans/central/LAYER_9_app_brand.md:9-16`, `plans/central/LAYER_9_app_brand.md:45-46`, and `plans/central/LAYER_9_app_brand.md:56-57`, matching `plans/CENTRAL_LAYERS_PROMPT.md:375-388`.

3. PASS — The plan locks the location to `Sources/SeshatCore/AppBrand/`, not `SeshatAppKit`, at `plans/central/LAYER_9_app_brand.md:45`, `plans/central/LAYER_9_app_brand.md:54-56`, and `plans/central/LAYER_9_app_brand.md:72-76`. Current trunk also uses that location at `Sources/SeshatCore/AppBrand/AppBrand.swift:1-11`.

4. PASS — The plan consistently uses `displayName` rather than Manus' `name` spelling. See `plans/central/LAYER_9_app_brand.md:11-12`, `plans/central/LAYER_9_app_brand.md:56`, `plans/central/LAYER_9_app_brand.md:121`, and `plans/central/LAYER_9_app_brand.md:133-145`. Manus' alternative `name` property exists only in the reference artifact at `/tmp/manus-rename-bundle/Ninimma_UI_Bundle/swift/AppBrand.swift:27`.

5. PASS — The plan has the required three-stage shape. Stage 1 adds the new directory and tests at `plans/central/LAYER_9_app_brand.md:64-89`, Stage 2 enumerates the consumer swaps including `Logger`, `PasteInjector`, menu bar, onboarding, settings/history window titles, pill accessibility, and build metadata at `plans/central/LAYER_9_app_brand.md:91-197`, and Stage 3 removes leftovers at `plans/central/LAYER_9_app_brand.md:198-221`. Current trunk also shows the intended in-between state: Stage 1 exists at `Sources/SeshatCore/AppBrand/AppBrand.swift:1-36` and `Tests/SeshatCoreTests/AppBrand/AppBrandTests.swift:1-48`, while Stage 2 consumers still hard-code brand values in `Sources/SeshatCore/Logger.swift:4-10`, `Sources/SeshatAppKit/Paste/PasteInjector.swift:72-79`, `Sources/SeshatAppKit/MenuBar/StatusItemController.swift:151-183`, `Sources/SeshatAppKit/Settings/SettingsWindowController.swift:26`, and `Sources/SeshatAppKit/Notes/NotesWindowController.swift:23`.

6. PARTIAL — The per-step validation hooks do cite concrete `file:line` anchors, for example at `plans/central/LAYER_9_app_brand.md:74-78`, `plans/central/LAYER_9_app_brand.md:86-89`, `plans/central/LAYER_9_app_brand.md:101-104`, and `plans/central/LAYER_9_app_brand.md:123-126`. The closing validation checklist at `plans/central/LAYER_9_app_brand.md:242-251` falls back to generic assertions without concrete produced-code anchors, which is weaker than the master requirement at `plans/CENTRAL_LAYERS_PROMPT.md:17`.

7. PASS — The plan does perform the required semantic duplicate audit. It identifies the logger subsystem duplication at `plans/central/LAYER_9_app_brand.md:25`, then routes it to `AppBrand.logSubsystem` in `plans/central/LAYER_9_app_brand.md:94-104`; it also identifies the duplicated version/build parsing and display helper at `plans/central/LAYER_9_app_brand.md:37`, `plans/central/LAYER_9_app_brand.md:56`, and `plans/central/LAYER_9_app_brand.md:186-221`. Those are the real duplicates on trunk today at `Sources/SeshatCore/Logger.swift:4-10`, `Sources/SeshatCore/AppBrand/AppBrand.swift:3-35`, and `Sources/SeshatAppKit/MenuBar/BuildInfo.swift:3-23`.

8. PARTIAL — The written plan follows the Stage 1 new-directory rule at authorship time with `Sources/SeshatCore/AppBrand/` and `Tests/SeshatCoreTests/AppBrand/` in `plans/central/LAYER_9_app_brand.md:54-56`, `plans/central/LAYER_9_app_brand.md:67-89`. Against the current SHA, those directories are no longer actually new because trunk already contains `Sources/SeshatCore/AppBrand/AppBrand.swift:1-36` and `Tests/SeshatCoreTests/AppBrand/AppBrandTests.swift:1-48`, so the plan now needs a state refresh before someone treats Stage 1 as still collision-free greenfield work.

9. PASS — Stages 1-3 stay behavior-neutral with respect to the later rename pass. The plan keeps `displayName = "Seshat"` and `bundleIdentifier = "com.nitkrar.seshat"` in scope and validation language at `plans/central/LAYER_9_app_brand.md:11-15`, `plans/central/LAYER_9_app_brand.md:76-77`, and `plans/central/LAYER_9_app_brand.md:99-103`, and it never bakes in `Ninimma` or `com.nitkrar.personal_scribe`. Current trunk Stage 1 matches that neutrality at `Sources/SeshatCore/AppBrand/AppBrand.swift:4-11`.

10. PARTIAL — This is the main substantive plan gap. The base Layer 9 surface in `plans/central/LAYER_9_app_brand.md:45-46`, `plans/central/LAYER_9_app_brand.md:56-57`, `plans/central/LAYER_9_app_brand.md:76-77`, and `plans/central/LAYER_9_app_brand.md:243-245` predates the Wave A bootstrap extension, so it does not yet include Manus' added `tagline`, `pronunciation`, `shortDescription`, `About.*`, and `Assets.*` fields declared at `/tmp/manus-rename-bundle/Ninimma_UI_Bundle/swift/AppBrand.swift:29-36` and `/tmp/manus-rename-bundle/Ninimma_UI_Bundle/swift/AppBrand.swift:49-94`. These are extension-needed-at-Stage-1 gaps, not a reason to mark the original plan broken.

11. PASS — Deferring Manus' SwiftUI convenience views is correct. The plan intentionally keeps Stage 1 data-only and explicitly says `No AppKit import` at `plans/central/LAYER_9_app_brand.md:56`. The Manus convenience views depend on `AppTheme` at `/tmp/manus-rename-bundle/Ninimma_UI_Bundle/swift/AppBrand.swift:134-173`, while trunk's compiled theme namespace is still `SeshatTheme` at `Sources/SeshatAppKit/Theme/SeshatTheme.swift:1-24`. Layer 9 should not absorb those Phase 2 presentation concerns yet.

12. PASS — The inter-layer dependency story is sound. The plan correctly marks Layer 9 as mostly standalone, parallelizable in Stage 1, and only dependent on Layer 1 for the shared TCC deep-link API at `plans/central/LAYER_9_app_brand.md:17-20`, `plans/central/LAYER_9_app_brand.md:58-61`, `plans/central/LAYER_9_app_brand.md:175-184`, and `plans/central/LAYER_9_app_brand.md:256-258`, matching `plans/CENTRAL_LAYERS_PROMPT.md:179-180`. The consumer spread at `plans/central/LAYER_9_app_brand.md:22-39` also correctly shows that many surfaces read brand strings.

## Cross-layer concerns

- No hard conflict with Layers 2, 4, 5, 6, 7, or 8 is visible from the current plans. Layer 9 remains mostly standalone per `plans/central/LAYER_9_app_brand.md:17-20` and `plans/central/LAYER_9_app_brand.md:256-258`.
- Layer 1 dependency is still correct, not a conflict: Layer 9's TCC deep-link cleanup waits for Layer 1's shared `systemSettingsDeepLink` API at `plans/central/LAYER_9_app_brand.md:18-20`, `plans/central/LAYER_9_app_brand.md:61`, and `plans/central/LAYER_9_app_brand.md:175-184`, matching `plans/CENTRAL_LAYERS_PROMPT.md:179-180`.
- Layer 3 needs a citation refresh once Layer 9 Step 2.9 or 3.2 lands. `plans/central/LAYER_3_settings.md:123-124` still points implementers at `Sources/SeshatAppKit/MenuBar/BuildInfo.swift:3-23` as the bundle-metadata owner, while Layer 9 plans to move or delete that ownership at `plans/central/LAYER_9_app_brand.md:186-221`. That is documentation drift, not a design mismatch.

## Stale file:line citations

- None confirmed in the cited trunk anchors I verified. The current drift is semantic rather than broken anchors: `plans/central/LAYER_9_app_brand.md:67-89` still treats `Sources/SeshatCore/AppBrand/AppBrand.swift:1-36` and `Tests/SeshatCoreTests/AppBrand/AppBrandTests.swift:1-48` as future Stage 1 work even though those files already exist on trunk.
