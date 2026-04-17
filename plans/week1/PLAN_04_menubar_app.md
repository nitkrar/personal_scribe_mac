# Plan 04: Menu Bar App + Permission Flow
**Goal**: Ship a `MenuBarExtra` SwiftUI app (`PSAppKit` executable target) with record/stop button, live state display from `SessionCoordinator.stateStream()`, and a production `AppKitMicrophonePermissionRequester` implementing `MicrophonePermissionRequesting`. Plan 99 wires it to production audio + transcription.
**Architecture**: SwiftUI `MenuBarExtra` + minimal `AppDelegate`; pure view-model that derives UI state from `SessionState`; `AVCaptureDevice.requestAccess` wrapped as `MicrophonePermissionRequesting` conformer.
**Tech Stack**: SwiftUI (macOS 14+), AppKit bridging, AVFoundation (permission-check only), Swift Concurrency, XCTest.
**Depends on**: Plan 00 Section C.2, C.3, C.4, D.5, D.6, G (contract); Plan 01 (scaffold).
**Plan 00 contract read**: Section C.2 (MicrophonePermissionRequesting), C.3 (SessionCoordinator), D.6 (ownership), G (Plan 04 symbols).

## Scope Guardrails
- Observe `SessionCoordinator.stateStream()` only.
- Never define a second `SessionState`, `SessionCoordinator`, `TranscriptionResult`, `MicrophonePermissionRequesting`, or `PSLogger`.
- Never create `Sources/PSAppKit/Composition/AppComposition.swift`.
- Never import `PSAudio` or `PSTranscription` from `PSAppKit` source outside future `Composition/`.
- Keep all UI-facing types on `@MainActor`.
- Use `PSLogger(category: PSLogCategory.ui)` for UI and lifecycle events.
- Tests should target pure logic and scene-model behavior; do not render `MenuBarExtra` directly in tests.

## Planned File Layout
```text
Sources/PSAppKit/
  PersonalScribeApp.swift
  AppDelegate.swift
  Permissions/
    AppKitMicrophonePermissionRequester.swift
  MenuBar/
    MicrophonePermissionState.swift
    MenuBarStatusIcon.swift
    RecordButtonViewModel.swift
    MenuBarSceneModel.swift
    MenuBarScene.swift
    RecordButtonView.swift
    LastResultView.swift
Tests/PSAppKitTests/
  DevelopmentComposition.swift
  AppKitMicrophonePermissionRequesterTests.swift
  RecordButtonViewModelTests.swift
  MenuBarStatusIconTests.swift
  MenuBarSceneModelTests.swift
  MenuBarFlowIntegrationTests.swift
  ManualAppVerification.md
```

## A. Development-time Composition Choice

### Decision
Choose **Option A**.

`PersonalScribeApp` is an injectable app shell, not a temporary fake composition root. Plan 04 develops and tests the shell with a real `SessionCoordinator` built from shared fakes in `Tests/PSAppKitTests/DevelopmentComposition.swift`. Plan 99 later adds the production bootstrap that injects `AppComposition.makeSessionCoordinator()` and `AppComposition.makeMicrophonePermissionRequester()`.

### Consequence
The literal zero-argument production `@main` bootstrap is finalized in Plan 99, not Plan 04. Plan 04 still owns the real app-shell type in `PersonalScribeApp.swift`, the menu bar UI, the permission flow, and all tests around them.

If someone insists that Plan 04 must also hardcode a temporary `@main` with fake dependencies, that is Option B and should be rejected as out of contract.

### Test-only `DevelopmentComposition` Shape
This helper lives only under `Tests/PSAppKitTests/`.

```swift
import Foundation
import PSCore
import PSSession
import PSTestSupport

@MainActor
enum DevelopmentComposition {
    static func makeCoordinator(
        buffers: [PCMBuffer] = [],
        result: TranscriptionResult,
        captureError: PSError? = nil,
        transcribeError: PSError? = nil,
        logger: PSLogger = PSLogger(category: PSLogCategory.ui)
    ) -> SessionCoordinator

    static func makePermissionRequester(
        initialState: MicrophonePermissionState = .notYetRequested,
        requestedDecision: Bool = true
    ) -> StubMicrophonePermissionRequester
}
```

### Why closures, not a new coordinator protocol
The menu layer needs seams for testing:
- state observation
- toggle action
- last result lookup
- settings opening
- clipboard writing

Those seams should be closures injected into a scene model. Do not add a `SessionCoordinating` or `SessionObserving` protocol. Plan 00 Section D.7 forbids creating a duplicate observer wrapper around `SessionCoordinator`.

### Plan 99 integration note
Plan 99 should wire:
- the single app-lifetime coordinator from `AppComposition`
- the production permission requester from `AppComposition`
- a thin `@main` entry point that injects those values into `PersonalScribeApp`

Plan 04 must only document that future shape, not create it.

## B. Planned APIs And View-model Signatures

### `PersonalScribeApp`
```swift
import SwiftUI
import PSCore
import PSSession

@MainActor
struct PersonalScribeApp: App {
    init(
        coordinator: SessionCoordinator,
        permissionRequester: any MicrophonePermissionRequesting,
        permissionStateProvider: @escaping @MainActor () -> MicrophonePermissionState,
        logger: PSLogger = PSLogger(category: PSLogCategory.ui)
    )

    var body: some Scene { get }
}
```

### `AppDelegate`
```swift
import AppKit
import PSCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    init(
        onDidFinishLaunching: @escaping @MainActor () -> Void,
        onDidWake: @escaping @MainActor () -> Void,
        logger: PSLogger = PSLogger(category: PSLogCategory.ui)
    )

    func applicationDidFinishLaunching(_ notification: Notification)
    func applicationDidWake(_ notification: Notification)
}
```

### `MicrophonePermissionState`
```swift
import Foundation

@MainActor
enum MicrophonePermissionState: Equatable {
    case notYetRequested
    case granted
    case denied
}
```

### `AppKitMicrophonePermissionRequester`
```swift
import AVFoundation
import PSCore

@MainActor
struct AppKitMicrophonePermissionRequester: MicrophonePermissionRequesting {
    init()

    init(
        statusProvider: @escaping @MainActor () -> AVAuthorizationStatus,
        accessRequester: @escaping @MainActor () async -> Bool
    )

    func requestAccess() async -> Bool
    func currentState() -> MicrophonePermissionState
}
```

### `MenuBarStatusIcon`
```swift
import Foundation
import PSCore

@MainActor
enum MenuBarIconTint: Equatable {
    case label
    case accent
    case destructive
}

@MainActor
struct MenuBarStatusIcon: Equatable {
    let systemImageName: String
    let tint: MenuBarIconTint

    static func make(
        sessionState: SessionState,
        permissionState: MicrophonePermissionState
    ) -> MenuBarStatusIcon
}
```

### `RecordButtonViewModel`
```swift
import Foundation
import PSCore

@MainActor
enum RecordButtonTint: Equatable {
    case accent
    case destructive
    case secondary
}

@MainActor
struct RecordButtonViewModel: Equatable {
    let title: String
    let systemImageName: String
    let tint: RecordButtonTint
    let isEnabled: Bool

    static func make(from sessionState: SessionState) -> RecordButtonViewModel
}
```

### `MenuBarSceneModel`
```swift
import Foundation
import PSCore

@MainActor
final class MenuBarSceneModel: ObservableObject {
    @Published private(set) var sessionState: SessionState
    @Published private(set) var permissionState: MicrophonePermissionState
    @Published private(set) var latestTranscriptText: String?

    init(
        stateStream: @escaping @Sendable () -> AsyncStream<SessionState>,
        toggleAction: @escaping @Sendable () async -> Void,
        lastResultProvider: @escaping @Sendable () async -> TranscriptionResult?,
        permissionRequester: any MicrophonePermissionRequesting,
        permissionStateProvider: @escaping @MainActor () -> MicrophonePermissionState,
        clipboardWriter: @escaping @MainActor (String) -> Void,
        openSettings: @escaping @MainActor () -> Void,
        logger: PSLogger = PSLogger(category: PSLogCategory.ui)
    )

    var statusIcon: MenuBarStatusIcon { get }
    var recordButton: RecordButtonViewModel { get }

    func startObserving()
    func handleRecordButtonTap() async
    func requestMicrophoneAccess() async
    func copyLatestTranscript()
    func openMicrophonePrivacySettings()
}
```

### `MenuBarScene`
```swift
import SwiftUI

@MainActor
struct MenuBarScene: View {
    init(model: MenuBarSceneModel)

    var body: some View { get }
}
```

### `RecordButtonView`
```swift
import SwiftUI

@MainActor
struct RecordButtonView: View {
    let viewModel: RecordButtonViewModel
    let action: @MainActor () async -> Void

    var body: some View { get }
}
```

### `LastResultView`
```swift
import SwiftUI

@MainActor
struct LastResultView: View {
    let text: String?
    let onCopy: @MainActor () -> Void

    var body: some View { get }
}
```

### Minimal real SwiftUI snippets
`MenuBarScene`:

```swift
import SwiftUI
import PSCore

@MainActor
struct MenuBarScene: View {
    @ObservedObject var model: MenuBarSceneModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("PersonalScribe").font(.headline)
            Text(stateLabel(for: model.sessionState))
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if model.permissionState != .granted {
                Button(permissionButtonTitle) {
                    Task {
                        if model.permissionState == .denied {
                            model.openMicrophonePrivacySettings()
                        } else {
                            await model.requestMicrophoneAccess()
                        }
                    }
                }
            }

            RecordButtonView(viewModel: model.recordButton, action: model.handleRecordButtonTap)
            LastResultView(text: model.latestTranscriptText, onCopy: model.copyLatestTranscript)
        }
        .padding(14)
        .frame(minWidth: 280)
        .task { model.startObserving() }
    }
}
```

## C. Task Breakdown

Each step is one red-green-refactor cycle with one commit. Keep each iteration narrow and use the smallest relevant `swift test --filter ...` command first.

### Step 1. `AppKitMicrophonePermissionRequester` scaffold + compile
Goal:
- add the production requester in `Sources/PSAppKit/Permissions/`
- prove it conforms to `MicrophonePermissionRequesting`

Files:
- `Sources/PSAppKit/Permissions/AppKitMicrophonePermissionRequester.swift`
- `Tests/PSAppKitTests/AppKitMicrophonePermissionRequesterTests.swift`

Red:
- add `testRequesterConformsToSharedProtocol`
- instantiate `let requester: any MicrophonePermissionRequesting = AppKitMicrophonePermissionRequester()`

Green:
- add the concrete type
- add `requestAccess() async -> Bool`
- add app-owned `currentState()` helper for the UI layer

Implementation notes:
- `requestAccess()` should bridge `AVCaptureDevice.requestAccess(for: .audio)` via `withCheckedContinuation`
- production code path uses `AVCaptureDevice.authorizationStatus(for: .audio)`
- no logging to `print()`

Pass:
```bash
swift test --filter AppKitMicrophonePermissionRequesterTests/testRequesterConformsToSharedProtocol
```

Commit:
```bash
git commit -m "plan-04 step 1: scaffold microphone permission requester"
```

### Step 2. Permission states and cached-decision behavior
Goal:
- introduce the three-state permission UI model
- make `requestAccess()` update future `currentState()` results

Files:
- `Sources/PSAppKit/MenuBar/MicrophonePermissionState.swift`
- `Sources/PSAppKit/Permissions/AppKitMicrophonePermissionRequester.swift`
- `Tests/PSAppKitTests/AppKitMicrophonePermissionRequesterTests.swift`

Red:
- `testCurrentStateMapsNotDeterminedToNotYetRequested`
- `testCurrentStateMapsAuthorizedToGranted`
- `testCurrentStateMapsDeniedToDenied`
- `testRequestAccessCachesGrantedDecision`
- `testRequestAccessCachesDeniedDecision`

Green:
- map `.notDetermined` -> `.notYetRequested`
- map `.authorized` -> `.granted`
- map `.denied` and `.restricted` -> `.denied`
- if already granted, `requestAccess()` returns `true` without prompting
- if already denied, `requestAccess()` returns `false` without prompting

Refactor:
- keep the AVFoundation translation in a private helper
- use the internal init with injected `statusProvider` and `accessRequester` to unit test without a real prompt

Pass:
```bash
swift test --filter AppKitMicrophonePermissionRequesterTests
```

Commit:
```bash
git commit -m "plan-04 step 2: add microphone permission state machine"
```

### Step 3. Deny path updates UI state
Goal:
- prove that a `false` result from `requestAccess()` becomes `.denied` in UI state

Files:
- `Sources/PSAppKit/MenuBar/MenuBarSceneModel.swift`
- `Tests/PSAppKitTests/MenuBarSceneModelTests.swift`

Red:
- `testRequestingAccessUpdatesPermissionStateToDeniedWhenPromptReturnsFalse`

Green:
- add `MenuBarSceneModel`
- inject `permissionRequester` and `permissionStateProvider`
- implement `requestMicrophoneAccess()`

Behavior:
- log the tap
- await `permissionRequester.requestAccess()`
- refresh `permissionState` from `permissionStateProvider`
- leave `sessionState` untouched

Important rule:
- permission state is separate from session state
- this is allowed because it is app-owned UI state, not a second recording state machine

Pass:
```bash
swift test --filter MenuBarSceneModelTests/testRequestingAccessUpdatesPermissionStateToDeniedWhenPromptReturnsFalse
```

Commit:
```bash
git commit -m "plan-04 step 3: connect deny path to scene model"
```

### Step 4. `RecordButtonViewModel` pure derivation
Goal:
- factor button title, icon, tint token, and enabled state into a pure helper

Files:
- `Sources/PSAppKit/MenuBar/RecordButtonViewModel.swift`
- `Tests/PSAppKitTests/RecordButtonViewModelTests.swift`

Red:
- `testIdleStateMapsToRecordButton`
- `testRecordingStateMapsToStopButton`
- `testTranscribingStateMapsToBusyDisabledButton`
- `testErrorStateMapsToRecordAgainButton`

Green:
- add `RecordButtonTint`
- add `RecordButtonViewModel.make(from:)`

Recommended mapping:
- `.idle` -> `Record`, `mic.circle.fill`, `.accent`, enabled
- `.recording` -> `Stop`, `stop.circle.fill`, `.destructive`, enabled
- `.transcribing` -> `Transcribing…`, `waveform.circle.fill`, `.secondary`, disabled
- `.error` -> `Record Again`, `arrow.clockwise.circle.fill`, `.accent`, enabled

Refactor:
- keep this free of permission knowledge
- keep this free of AppKit types

Pass:
```bash
swift test --filter RecordButtonViewModelTests
```

Commit:
```bash
git commit -m "plan-04 step 4: add record button view model"
```

### Step 5. `RecordButtonViewModel.onTap` equivalent: button tap routes to `SessionCoordinator.toggle()`
Goal:
- ensure the UI action delegates to the shared coordinator and nothing else

Files:
- `Sources/PSAppKit/MenuBar/MenuBarSceneModel.swift`
- `Sources/PSAppKit/MenuBar/RecordButtonView.swift`
- `Tests/PSAppKitTests/MenuBarSceneModelTests.swift`

Red:
- `testHandleRecordButtonTapInvokesInjectedToggleAction`

Green:
- add `handleRecordButtonTap() async`
- implement `RecordButtonView`
- wrap the button action in `Task { await action() }`

Rules:
- do not mutate `sessionState` optimistically
- the UI should wait for `stateStream()` to report the real state
- ignored toggles during `.transcribing` must remain the coordinator’s responsibility

Pass:
```bash
swift test --filter MenuBarSceneModelTests/testHandleRecordButtonTapInvokesInjectedToggleAction
```

Commit:
```bash
git commit -m "plan-04 step 5: route button tap to session coordinator"
```

### Step 6. Observer task for `stateStream()`
Goal:
- mirror the authoritative session actor into app-owned published UI state

Files:
- `Sources/PSAppKit/MenuBar/MenuBarSceneModel.swift`
- `Tests/PSAppKitTests/MenuBarSceneModelTests.swift`

Red:
- `testStartObservingConsumesScriptedStateStreamInOrder`
- scripted sequence: `.idle`, `.recording`, `.transcribing`, `.idle`

Green:
- implement `startObserving()`
- store the observation task
- ignore repeated `startObserving()` calls
- cancel the task in `deinit`

Required loop:

```swift
Task {
    for await state in stateStream() {
        await MainActor.run {
            self.sessionState = state
        }
    }
}
```

Add the extra `lastResult()` refresh:
- on initial start
- on transition to `.idle`
- on transition to `.error`

Reason:
- the popover needs `lastResult()?.text`
- state updates and latest-result refresh should stay on the main actor boundary

Pass:
```bash
swift test --filter MenuBarSceneModelTests/testStartObservingConsumesScriptedStateStreamInOrder
```

Commit:
```bash
git commit -m "plan-04 step 6: observe session state stream"
```

### Step 7. `LastResultView` and copy-to-clipboard
Goal:
- show `lastResult()?.text`
- add one-click copy

Files:
- `Sources/PSAppKit/MenuBar/LastResultView.swift`
- `Sources/PSAppKit/MenuBar/MenuBarSceneModel.swift`
- `Tests/PSAppKitTests/MenuBarSceneModelTests.swift`

Red:
- `testCopyLatestTranscriptWritesCurrentTranscriptToClipboard`
- `testCopyLatestTranscriptDoesNothingWhenTranscriptIsMissing`

Green:
- add `latestTranscriptText`
- add `copyLatestTranscript()`
- inject `clipboardWriter`
- add `LastResultView`

Production clipboard closure:
```swift
{ text in
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    pasteboard.setString(text, forType: .string)
}
```

Explicit scope note:
- Week 1 writes the string directly
- full pasteboard save/restore belongs to Week 2 injection work

Pass:
```bash
swift test --filter MenuBarSceneModelTests
```

Commit:
```bash
git commit -m "plan-04 step 7: add latest transcript copy view"
```

### Step 8. Permission-denied affordance and settings deep link
Goal:
- show the correct CTA when permission is missing
- deep-link denied users to microphone privacy settings

Files:
- `Sources/PSAppKit/MenuBar/MenuBarScene.swift`
- `Sources/PSAppKit/MenuBar/MenuBarSceneModel.swift`
- `Tests/PSAppKitTests/MenuBarSceneModelTests.swift`

Red:
- `testOpenMicrophonePrivacySettingsInvokesInjectedSettingsAction`
- `testDeniedPermissionStateExposesSettingsAffordance`
- `testNotYetRequestedPermissionStateExposesGrantButton`

Green:
- add `openMicrophonePrivacySettings()`
- inject `openSettings`
- update `MenuBarScene` button copy

Required URL:
```swift
x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone
```

Production open closure:
```swift
{
    guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") else {
        return
    }
    NSWorkspace.shared.open(url)
}
```

Rules:
- `.notYetRequested` -> show `Grant Microphone Access`
- `.denied` -> show `Open System Settings → Privacy → Microphone`
- `.granted` -> hide permission CTA

Pass:
```bash
swift test --filter MenuBarSceneModelTests
```

Commit:
```bash
git commit -m "plan-04 step 8: add denied permission settings affordance"
```

### Step 9. Menu bar glyph selection logic
Goal:
- keep status icon choice pure and unit-testable

Files:
- `Sources/PSAppKit/MenuBar/MenuBarStatusIcon.swift`
- `Tests/PSAppKitTests/MenuBarStatusIconTests.swift`

Red:
- `testGrantedIdleMapsToMic`
- `testGrantedRecordingMapsToFilledMicWithRedTint`
- `testDeniedAlwaysMapsToMicSlash`

Green:
- add `MenuBarIconTint`
- add `MenuBarStatusIcon.make(sessionState:permissionState:)`

Mapping:
- denied -> `mic.slash`, `.label`
- granted + idle -> `mic`, `.label`
- granted + recording -> `mic.fill`, `.destructive`
- granted + transcribing -> `mic.fill`, `.accent`
- granted + error -> `mic`, `.label`
- not-yet-requested + idle -> `mic`, `.label`

Rule:
- the pure function is the tested source of truth
- SwiftUI/AppKit image construction adapts it later

Pass:
```bash
swift test --filter MenuBarStatusIconTests
```

Commit:
```bash
git commit -m "plan-04 step 9: add menu bar icon mapping"
```

### Step 10. App lifecycle and bootstrap wiring
Goal:
- keep launch and wake handling minimal
- start session observation once

Files:
- `Sources/PSAppKit/AppDelegate.swift`
- `Sources/PSAppKit/PersonalScribeApp.swift`
- `Tests/PSAppKitTests/MenuBarSceneModelTests.swift`

Red:
- `testStartObservingIsIdempotentAcrossRepeatedLifecycleCalls`

Green:
- add `AppDelegate`
- inject `onDidFinishLaunching`
- inject `onDidWake`
- call `startObserving()` from the launch path

Rules:
- `applicationDidFinishLaunching` logs and starts observation
- `applicationDidWake` logs and may reassert observation, but must not create duplicates
- no model prewarm in Plan 04
- no permission auto-prompt on app launch unless product later decides otherwise

`PersonalScribeApp` responsibilities:
- own the `MenuBarSceneModel`
- own `@NSApplicationDelegateAdaptor`
- expose a `MenuBarExtra`
- source the icon from `model.statusIcon`

Pass:
```bash
swift test --filter MenuBarSceneModelTests/testStartObservingIsIdempotentAcrossRepeatedLifecycleCalls
```

Commit:
```bash
git commit -m "plan-04 step 10: add app lifecycle bootstrap"
```

### Step 11. Integration test with real `SessionCoordinator` and shared fakes
Goal:
- prove the menu layer works with the shared coordinator contract, not a shadow abstraction

Files:
- `Tests/PSAppKitTests/DevelopmentComposition.swift`
- `Tests/PSAppKitTests/MenuBarFlowIntegrationTests.swift`

Red:
- `testRecordStopTranscribeIdleFlowPublishesLatestResult`

Flow:
1. build a real `SessionCoordinator` with `FakeAudioCapturing` and `FakeTranscriber`
2. create `MenuBarSceneModel` from the coordinator closures
3. start observing
4. tap record
5. observe `.recording`
6. tap stop
7. observe `.transcribing`
8. observe `.idle`
9. assert `latestTranscriptText == fakeResult.text`

Green:
- use only `FakeAudioCapturing` and `FakeTranscriber` from `PSTestSupport`
- do not add a fake coordinator
- prefer awaiting published values over arbitrary sleeps

Pass:
```bash
swift test --filter MenuBarFlowIntegrationTests
```

Commit:
```bash
git commit -m "plan-04 step 11: add menu bar integration flow test"
```

### Step 12. Manual verification runbook
Goal:
- capture the real local-launch checklist for the Week 1 menu bar app

Files:
- `Tests/PSAppKitTests/ManualAppVerification.md`

Green only:
- document `swift run PSAppKit`
- document first launch with not-yet-requested permission
- document grant path
- document deny path
- document record/stop flow
- document latest-result copy
- document settings deep link
- document sleep/wake expectations

Must include:
- Week 1 copy overwrites the string pasteboard
- full clipboard save/restore is Week 2 scope
- icon tint may vary depending on how `MenuBarExtra` status-item tint behaves on the target macOS build

Smoke check before commit:
```bash
swift test --filter MenuBarFlowIntegrationTests
```

Commit:
```bash
git commit -m "plan-04 step 12: add manual app verification runbook"
```

## D. Dependency Table

### Parallel groups
| Group | Steps | Reason |
|---|---|---|
| A | 1, 4, 9 | requester scaffold, button derivation, and icon derivation are independent |
| B | 2, 7 | permission-state mapping and copy UI are independent once base files exist |
| C | 3, 5, 6 | same scene-model file; keep one implementer on the critical path |
| D | 8, 10 | settings affordance and lifecycle glue can proceed after the scene model exists |
| E | 11, 12 | final verification and runbook land last |

### Strict dependencies
| Step | Depends on | Why |
|---|---|---|
| 1 | Plan 01 | target and test scaffold must exist |
| 2 | 1 | concrete requester must exist first |
| 3 | 2 | UI deny path needs permission state |
| 4 | Plan 00 | only shared `SessionState` is needed |
| 5 | 4 | button view consumes `RecordButtonViewModel` |
| 6 | 3, 5 | scene model needs action seams before observation logic |
| 7 | 6 | copy UI depends on observed latest result |
| 8 | 3 | denied CTA depends on permission state |
| 9 | 2, 4 | icon derivation depends on session and permission state |
| 10 | 6, 9 | app shell should consume scene model and icon only after both exist |
| 11 | 6, 7 | integration needs observation and last-result display |
| 12 | 10, 11 | runbook should describe the implemented shell and verified flow |

### Recommended execution order
1. Step 1
2. Step 4
3. Step 9
4. Step 2
5. Step 3
6. Step 5
7. Step 6
8. Step 7
9. Step 8
10. Step 10
11. Step 11
12. Step 12

## E. Handoff Signals
- `PSAppKit` builds with the injectable app shell, app delegate, permission requester, scene model, and popover views.
- `AppKitMicrophonePermissionRequester` conforms to `MicrophonePermissionRequesting`.
- Permission state is exactly three UI states: not-yet-requested, granted, denied.
- The menu bar popover displays current session state from `SessionCoordinator.stateStream()`.
- The record button action reaches `SessionCoordinator.toggle()` through an injected closure backed by the real coordinator.
- Latest transcript text comes from `lastResult()?.text`.
- Copy uses `NSPasteboard.general` directly and does not attempt full save/restore.
- Denied permission exposes `Open System Settings → Privacy → Microphone`.
- Status icon selection is covered by pure unit tests.
- No test tries to render `MenuBarExtra` directly.
- Integration coverage uses a real `SessionCoordinator` with `FakeAudioCapturing` and `FakeTranscriber`.
- No `PSAppKit` source outside future `Composition/` imports `PSAudio` or `PSTranscription`.
- No file exists at `Sources/PSAppKit/Composition/AppComposition.swift`.

Plan 99 can then do exactly three things:
- create `AppComposition.swift`
- wire the single production `SessionCoordinator`
- add the real production `@main` bootstrap that injects into `PersonalScribeApp`

## F. Logging Plan
Use `PSLogger(category: PSLogCategory.ui)` for launch, wake, observation start, duplicate-observer suppression, record taps, permission request/result, copy actions, and settings-opening. Do not log transcript contents by default. Do not use `print()`.

## G. Manual Verification Outline
The later `Tests/PSAppKitTests/ManualAppVerification.md` should include:

Launch:
```bash
swift run PSAppKit
```

Checklist:
1. Confirm a single menu bar item appears.
2. Confirm the initial state label reads idle.
3. If permission is not yet requested, confirm the grant-access button is visible.
4. Deny permission and confirm the icon changes to `mic.slash`.
5. Confirm the settings deep link opens the microphone privacy pane.
6. Grant permission and confirm record changes the state to recording.
7. Stop and confirm the state passes through transcribing back to idle.
8. Confirm latest transcript text appears.
9. Confirm copy writes the transcript string to the pasteboard.
10. Confirm sleep/wake does not create duplicate observation behavior.

Notes:
- Week 1 copy overwrites the string pasteboard; full save/restore is Week 2 scope; icon tint may vary depending on `MenuBarExtra` status-item behavior on the target macOS build.

## H. Open Questions
1. Should the denied-state CTA use the long exact label from the request, or a shorter button title plus explanatory text?
2. Is it acceptable if the menu bar icon uses glyph changes but the red tint is only reliably visible inside the popover for Week 1?
3. Should `.transcribing` use the same filled mic glyph as `.recording`, or a neutral non-red glyph?

## I. Completion Definition
Plan 04 is complete when:
- the app shell and menu bar popover exist in `PSAppKit`
- permission prompting is production-backed by AVFoundation in `PSAppKit/Permissions/`
- UI state is derived from shared contract types and app-owned permission state only
- tests cover button derivation, icon derivation, permission transitions, state observation, and fake-backed integration flow
- the plan leaves no dead-code composition path for Plan 99 to clean up
