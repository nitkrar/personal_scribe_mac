# Layer 9 Stage 1 — Code Review

## Verdict
APPROVED-WITH-NITS. Commit `8d866da` matches the Stage 1 contract in `plans/central/LAYER_9_app_brand.md:64-89`: it adds the namespace-only `AppBrand` API in the new core directory, keeps the locked `Seshat` / `com.nitkrar.seshat` values, and does not migrate existing consumers early in `Sources/SeshatCore/AppBrand/AppBrand.swift:3-35`. I did not find a new `[QUESTION-BRAND-2]` facet; the only issue is a narrow, non-blocking test-robustness nit around the live `version` vs `buildNumber` wiring.

## Findings by Severity
### Blockers
None.

### Major
None.

### Minor
None.

### Nits
- `Tests/SeshatCoreTests/AppBrand/AppBrandTests.swift:17-22` validates `AppBrand.version` and `AppBrand.buildNumber` against the same internal helpers used by `Sources/SeshatCore/AppBrand/AppBrand.swift:10-18`, not against a divergent live-value fixture. Because packaged builds currently write both `CFBundleShortVersionString` and `CFBundleVersion` from `${VERSION}` in `scripts/package.sh:151-156`, a swapped public-property wiring could slip past this smoke test even though helper-level parsing is covered separately in `Tests/SeshatCoreTests/AppBrand/AppBrandTests.swift:24-46`.

## Cross-Layer Concerns
None.

## Test Gaps
- `AppBrand` still lacks a public-surface proof that `version` reads `CFBundleShortVersionString` and `buildNumber` reads `CFBundleVersion` when the live values differ; the current smoke test is `testVersionAndBuildNumberReadFromMainBundleInfoDictionary` in `Tests/SeshatCoreTests/AppBrand/AppBrandTests.swift:17-22`.

## Summary
The Stage 1 implementation is faithful to the Layer 9 plan: `AppBrand` exposes the required fields, keeps the marketing URLs nil, stays within the new `Sources/SeshatCore/AppBrand/` and `Tests/SeshatCoreTests/AppBrand/` directories, and leaves all Stage 2 consumer migrations untouched. I found 0 blockers, 0 major, 0 minor, and 1 nit.

I did not identify a new `[QUESTION-BRAND-2]` facet beyond the already-tracked fallback choice. `scripts/package.sh:155-156` still populates `CFBundleVersion` for packaged builds, so the current `"dev"` fallback remains a non-release-path policy question rather than a Stage 1 code defect.
