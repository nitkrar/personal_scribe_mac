# Layer 5 Review

Verdict: NEEDS REVISION

Finding summary: critical 0, major 4, minor 2.

## Findings by checklist item

1. PASS — The do-not-diverge paragraph is present verbatim under `## Critical discipline` in `plans/central/LAYER_5_output.md:3-4`, matching `plans/CENTRAL_LAYERS_PROMPT.md:11-17`.

2. PARTIAL — The plan carries the paste/copy/streaming contract, `OutputMode` = `paste` / `copy` / `both`, an `@MainActor` `OutputService`, and `PasteOutputService` / `CopyOutputService` in `plans/central/LAYER_5_output.md:32-55` and `plans/central/LAYER_5_output.md:65-69`, which matches the already-landed trunk output layer. But the current master prompt text at `plans/CENTRAL_LAYERS_PROMPT.md:267-275` still specifies `.batch` / `.streaming`, `deliverBatch(text:) async -> OutputResult`, and `ClipboardBatchOutput` / `StreamedTypingOutput`. The plan is coherent with trunk, not with the current prompt file verbatim.

3. PASS — Streaming is first-class in the contract: `beginStream() -> any OutputStreamHandle`, `append(_:)`, and `finalize()` are explicit in `plans/central/LAYER_5_output.md:47-55`, and the chunk flow / transport decision / finalization rules are described in `plans/central/LAYER_5_output.md:85-90`.

4. PARTIAL — The plan is structured as Stage 1 / Stage 2 / Stage 3 and Stage 1 is scoped to `Sources/SeshatCore/Output/*` + `Sources/SeshatAppKit/Output/*` in `plans/central/LAYER_5_output.md:73-83` and `plans/central/LAYER_5_output.md:93-99`, but on current trunk those directories and files already exist. As written, the plan still reads like a pre-landing parallel-build step rather than a current-trunk execution plan.

5. PARTIAL — Every step includes validation bullets with `file:line` references in `plans/central/LAYER_5_output.md:131-136`, `plans/central/LAYER_5_output.md:167-172`, `plans/central/LAYER_5_output.md:205-209`, `plans/central/LAYER_5_output.md:252-257`, `plans/central/LAYER_5_output.md:289-294`, `plans/central/LAYER_5_output.md:321-324`, and `plans/central/LAYER_5_output.md:378-383`. But several Stage 1 citations are already stale against trunk because the files exist and are much shorter than the cited ranges; see `Stale file:line citations` below.

6. PARTIAL — The plan recognizes the duplicated output seams and schedules their removal in `plans/central/LAYER_5_output.md:7-9`, `plans/central/LAYER_5_output.md:67-69`, `plans/central/LAYER_5_output.md:138-154`, and `plans/central/LAYER_5_output.md:331-343`, but it does not include a dedicated forbidden-duplicates semantic audit. On current trunk the duplication state is already real: `PasteInjector` and `PasteOutputService` coexist, and the app-entry `clipboardWriter` closures coexist with `CopyOutputService`.

7. FAIL — The Stage 1 parallel-build collision rule is not satisfied against current trunk. The plan still claims `Sources/SeshatCore/Output/*`, `Sources/SeshatAppKit/Output/*`, and the matching test directories as fresh Stage 1 territory in `plans/central/LAYER_5_output.md:65`, `plans/central/LAYER_5_output.md:73-83`, and `plans/central/LAYER_5_output.md:107-209`, but those directories are already populated on trunk. That needs to be surfaced as a current-state collision / already-landed step, not left implicit.

8. PASS — The plan stays behavior-neutral with respect to future brand or copy flips. Stage 1 explicitly preserves current batch behavior in `plans/central/LAYER_5_output.md:152-154`, Stage 2 limits itself to ownership migration in `plans/central/LAYER_5_output.md:235-243` and `plans/central/LAYER_5_output.md:274-282`, and Stage 3 is framed as deletion-only in `plans/central/LAYER_5_output.md:361-369`.

9. PARTIAL — The bottom dependency section is directionally correct in `plans/central/LAYER_5_output.md:412-414`, and it matches the sibling dependency claims in `plans/central/LAYER_1_permissions.md:104`, `plans/central/LAYER_1_permissions.md:243`, and `plans/central/LAYER_3_settings.md:11`. But the Layer 5 step inventories never name the concrete rewire from direct AX probing and `SeshatPasteMode` / `PasteRestoreDelay` reads to Layer 1’s `PermissionService` and Layer 3’s centralized preference surface. The affected output files are introduced in `plans/central/LAYER_5_output.md:80-82` and never revisited in Stage 2.

10. PASS — The Stage 2 consumer list includes the session success hook, the menu-bar helper, and the conditional command-mode audit in `plans/central/LAYER_5_output.md:214-216`, with concrete sub-steps at `plans/central/LAYER_5_output.md:218-323`.

11. PASS — The plan explicitly acknowledges that trunk has no live command-mode output consumer and refuses to invent one. That is stated in `plans/central/LAYER_5_output.md:21-23`, `plans/central/LAYER_5_output.md:296-315`, and `plans/central/LAYER_5_output.md:317-324`.

12. PASS — The `[QUESTION]` markers are preserved and expanded at `plans/central/LAYER_5_output.md:392-396`.

## Cross-layer concerns

- Layers 1 and 3: `plans/central/LAYER_5_output.md:67-69`, `plans/central/LAYER_5_output.md:214-215`, and `plans/central/LAYER_5_output.md:412-414` say Layer 5 depends on `PermissionService` and the centralized paste preferences, but there is no explicit swap step for `PasteOutputService` or `AppKitOutputService` after Stage 1. Current trunk `Sources/SeshatAppKit/Output/PasteOutputService.swift:61-62` still reads `PasteRestoreDelay` directly, `Sources/SeshatAppKit/Output/PasteOutputService.swift:97-98` still reads `SeshatPasteMode` directly, and `Sources/SeshatAppKit/Output/PasteOutputService.swift:78-81` still probes AX directly.

- Layer 7: `plans/central/LAYER_5_output.md:71`, `plans/central/LAYER_5_output.md:214-216`, and `plans/central/LAYER_5_output.md:246-255` move output into `SessionCoordinator` and keep successful transcription `.idle` even when output falls back or throws a non-fatal output error. `plans/central/LAYER_7_pipeline.md:90-99`, `plans/central/LAYER_7_pipeline.md:155-166`, `plans/central/LAYER_7_pipeline.md:203-215`, and `plans/central/LAYER_7_pipeline.md:374-375` instead make output a pipeline stage owned by `SessionPipelineOrchestrator` and require typed output failures. The two plans need one explicit owner and one error-semantics rule.

## Stale file:line citations

- `plans/central/LAYER_5_output.md:108-113`, `plans/central/LAYER_5_output.md:132-136`, and `plans/central/LAYER_5_output.md:399` cite Stage 1 core files at oversized ranges that exceed current EOF:
  - `Sources/SeshatCore/Output/OutputMode.swift:1-20` (actual 5 lines)
  - `Sources/SeshatCore/Output/OutputTarget.swift:1-25` (actual 5 lines)
  - `Sources/SeshatCore/Output/OutputDelivery.swift:1-25` (actual 5 lines)
  - `Sources/SeshatCore/Output/OutputError.swift:1-40` (actual 6 lines)
  - `Sources/SeshatCore/Output/OutputStreamHandle.swift:1-30` (actual 5 lines)
  - `Sources/SeshatCore/Output/OutputService.swift:1-30` (actual 6 lines)

- `plans/central/LAYER_5_output.md:114`, `plans/central/LAYER_5_output.md:135`, and `plans/central/LAYER_5_output.md:386` cite `Tests/SeshatCoreTests/Output/OutputContractsTests.swift:1-140`, but the current trunk file is 95 lines long.

- `plans/central/LAYER_5_output.md:146-149`, `plans/central/LAYER_5_output.md:168-172`, and `plans/central/LAYER_5_output.md:386` cite Stage 1 AppKit implementation / test files at oversized ranges that exceed current EOF:
  - `Sources/SeshatAppKit/Output/PasteOutputService.swift:1-180` (actual 128 lines)
  - `Sources/SeshatAppKit/Output/CopyOutputService.swift:1-60` (actual 32 lines)
  - `Tests/SeshatAppKitTests/Output/PasteOutputServiceTests.swift:1-240` (actual 227 lines)
  - `Tests/SeshatAppKitTests/Output/CopyOutputServiceTests.swift:1-120` (actual 37 lines)

- `plans/central/LAYER_5_output.md:182-186`, `plans/central/LAYER_5_output.md:205-209`, and `plans/central/LAYER_5_output.md:386` cite later Stage 1 files at oversized ranges that exceed current EOF:
  - `Sources/SeshatAppKit/Output/AppKitOutputService.swift:1-140` (actual 41 lines)
  - `Sources/SeshatAppKit/Output/StreamingOutputHandle.swift:1-120` (actual 56 lines)
  - `Tests/SeshatAppKitTests/Output/AppKitOutputServiceTests.swift:1-160` (actual 86 lines)
  - `Tests/SeshatAppKitTests/Output/StreamingOutputHandleTests.swift:1-180` (actual 43 lines)
  - `plans/backlog/streaming-output-delivery-mechanism.md:1-80` (actual 57 lines)

- `plans/central/LAYER_5_output.md:229`, `plans/central/LAYER_5_output.md:255`, and `plans/central/LAYER_5_output.md:374` cite `Tests/SeshatSessionTests/SessionCoordinatorOutputTests.swift:1-200`, but that file is not present on current trunk. If it is intended as a future file, the plan should distinguish “new file to be created” from a current-trunk anchor.
