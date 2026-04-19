# Layer 1 Stage 1 Code Review

## 1. Verdict
NEEDS REVISION

## 2. Findings by severity

### Critical

1. `Sources/SeshatCore/Permissions/PermissionService.swift:3`

   Quote:
   ```swift
   @MainActor
   public protocol PermissionService: Sendable {
   ```

   Issue:
   The shared contract omits the layer's observable surface. `plans/central/LAYER_1_permissions.md:50,64-65` and `plans/CENTRAL_LAYERS_PROMPT.md:162-168` require one `@Published` dictionary that subscribers use to react to `refresh()`, but the protocol exposes only synchronous methods. As implemented, any `any PermissionService` consumer can only poll or downcast to `AppKitPermissionService`, which breaks the “single shared permission contract” and blocks the planned Layer 4 `AppStore` shape in `plans/central/LAYER_4_appstore.md:23-37`.

   Suggested fix shape:
   Expose the observable contract at the abstraction boundary, not only on the concrete class. The smallest fix is to make `PermissionService` carry a readable snapshot plus observation semantics, e.g. `ObservableObject` + `var statuses: [Permission: PermissionStatus] { get }`, and then update the fake service/tests to verify subscription through `any PermissionService`.

### Major

1. `Sources/SeshatAppKit/Permissions/Service/PermissionServiceDependencies.swift:102`

   Quote:
   ```swift
   ) { _ in
       Task { @MainActor in
           handler()
   ```

   Issue:
   The live `didBecomeActive` refresh is delivered asynchronously even though the observer is already registered on `.main` (`Sources/SeshatAppKit/Permissions/Service/PermissionServiceDependencies.swift:98-101`). `plans/central/LAYER_1_permissions.md:50,71,110` requires activation to re-read permissions when returning from System Settings; this extra task hop creates a stale-snapshot race where the app becomes active before `statuses` is refreshed. The current test only exercises `ActivationObserverSpy` (`Tests/SeshatAppKitTests/Permissions/AppKitPermissionServiceTests.swift:186-203`), so the live timing is unpinned.

   Suggested fix shape:
   Invoke the handler synchronously on the main actor when the main-queue notification fires, and add a test that covers the live observer wiring or equivalent queue semantics.

2. `Sources/SeshatCore/InputMonitoringPermissionProbe.swift:6`

   Quote:
   ```swift
   public enum InputMonitoringPermissionState: Sendable, Equatable {
       case notDetermined
       case granted
   ```

   Issue:
   This is the legacy IM-only surface that Step 1.1 says must remain untouched until Stage 3 (`plans/central/LAYER_1_permissions.md:83-94`; `plans/CENTRAL_LAYERS_PROMPT.md:44-59`). The 93ce06c fix-forward renamed the pre-existing `Sources/SeshatCore/PermissionStatus.swift` file to avoid a basename collision with the new Stage 1 `Sources/SeshatCore/Permissions/PermissionStatus.swift`, so Stage 1 no longer lands as “new files in new directories” only.

   Suggested fix shape:
   Keep the legacy file path untouched and avoid the collision by renaming the new Stage 1 file, not the old one. The type can still be `PermissionStatus`; only the filename needs to change. If that is no longer practical, amend the plan and downstream deletion checklists explicitly before continuing Layer 1.

3. `Tests/SeshatAppKitTests/DevelopmentComposition.swift:8`

   Quote:
   ```swift
   static func makeTestingSessionCoordinator(
       buffers: [PCMBuffer] = defaultBuffers(),
       result: TranscriptionResult = defaultResult(),
   ```

   Issue:
   The 93ce06c fix-forward bundled unrelated non-permissions test maintenance into the Layer 1 Stage 1 stack. This file, plus `Tests/SeshatAppKitTests/MenuBarSceneModelTests.swift`, `Tests/SeshatAppKitTests/PillOverlayViewModelTests.swift`, `Tests/SeshatCoreTests/Preferences/PreferenceTests.swift`, and `Tests/SeshatSessionTests/SessionCoordinatorPreparationTests.swift`, are outside the Stage 1 permissions test directories named in `plans/central/LAYER_1_permissions.md:75,99-100,108-109`. That violates the Stage 1 isolation rule from `plans/CENTRAL_LAYERS_PROMPT.md:44-59` and means this layer no longer lands independently of unrelated app/session behavior drift.

   Suggested fix shape:
   Split the stale-test repairs into a separate commit outside the Layer 1 Stage 1 review scope, leaving the permissions stack limited to new permissions files plus any narrowly scoped build fix that is explicitly surfaced as a plan divergence.

### Minor

1. `Sources/SeshatAppKit/Permissions/Service/AppKitPermissionService.swift:7`

   Quote:
   ```swift
   final class AppKitPermissionService: ObservableObject, PermissionService, @unchecked Sendable {
   ```

   Issue:
   `@unchecked Sendable` is broader than needed on a `@MainActor` service, and it suppresses compiler enforcement on the exact concurrency boundary this layer is supposed to harden. The same pattern is repeated in the contract test stub at `Tests/SeshatCoreTests/Permissions/PermissionServiceContractTests.swift:41`. Given the review brief's explicit Swift 6 concurrency check, this is avoidable risk rather than a style preference.

   Suggested fix shape:
   Remove `@unchecked Sendable` from main-actor-isolated service/test types and let the compiler prove sendability. If any stored dependency still needs annotation, mark that narrower wrapper as `Sendable` or `@unchecked Sendable` with a local justification instead of silencing checks on the whole service.

## 3. Cross-layer concerns

- Layer 4 currently plans to store `private let permissions: any PermissionService` inside `AppStore` and publish `snapshot.permissions` from that source (`plans/central/LAYER_4_appstore.md:23-37`). Until Layer 1 exposes observation on the protocol itself, Layer 4 will have to downcast or duplicate refresh wiring outside the permissions layer.
- The legacy-file rename from `Sources/SeshatCore/PermissionStatus.swift` to `Sources/SeshatCore/InputMonitoringPermissionProbe.swift` leaves Layer 1 plan citations and the Stage 3 deletion checklist stale. That drift should be corrected before later layers use the plan as an execution artifact.
- No Stage 2 consumer migrations or new permission-driven deletions are present in the reviewed permissions source itself beyond the isolation breaches above, and `AVAudioCaptureService` remains untouched as required.

## 4. Test coverage gaps

- `Tests/SeshatCoreTests/Permissions/PermissionServiceContractTests.swift:7-37` only exercises synchronous methods on a stub; it does not verify the observable contract the plan requires, which is how the protocol-level observation gap slipped through.
- `Tests/SeshatAppKitTests/Permissions/AppKitPermissionServiceTests.swift:186-203` verifies activation refresh only through `ActivationObserverSpy`, not the live `NotificationCenter`/main-queue path. The asynchronous `Task` hop at `Sources/SeshatAppKit/Permissions/Service/PermissionServiceDependencies.swift:102-105` therefore has no direct coverage.
- The new service suite does not cover the “already granted is a no-op” request paths for all three permissions. The plan asked for `RequestOutcome` behavior coverage broadly (`plans/central/LAYER_1_permissions.md:100,216`), and those branches are currently unpinned.

## 5. Summary

Verdict remains `NEEDS REVISION`.

Finding counts:
- Critical: 1
- Major: 3
- Minor: 1

The main blocker is contract fidelity: Stage 1 created a live service, but not a fully observable `PermissionService` abstraction. The other issues are one activation-refresh race and two Stage 1 isolation violations introduced by the fix-forward commit.
