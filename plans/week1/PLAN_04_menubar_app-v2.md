# Plan 04: Menu Bar App + Permission Flow (v2)
**Goal**: Ship the Week 1 `SeshatAppKit` menu bar UI shell, permission flow, and view-model logic around the shared `SessionCoordinator` contract. Plan 04 does **not** ship a runnable `@main`; Plan 99 owns production bootstrap and manual launch.
**Architecture**: SwiftUI `MenuBarExtra` shell without `@main`; `MenuBarSceneModel` observes `SessionCoordinator` directly; app-owned microphone permission flow via `AppKitMicrophonePermissionRequester`; XCTest-driven verification at the view-model layer.
**Tech Stack**: SwiftUI (macOS 14+), AVFoundation permission APIs, Swift Concurrency, XCTest.
**Depends on**: Plan 00 Section C.2, C.3, C.4, D.6, D.7, G (contract); Plan 01 (scaffold).
**Plan 00 contract read**: Section C.2 (`MicrophonePermissionRequesting`), Section C.3 (`SessionCoordinator`), Section D.6 (ownership), Section D.7 (forbidden duplicates), Section G (Plan 04 symbols).

## Changes from v1 → v2
- Replaced the non-compilable `stateStream` sync closure seam with direct `SessionCoordinator` injection and `await coordinator.stateStream()`.
- Moved record-button permission gating into `MenuBarSceneModel.handleRecordButtonTap()` so `.notYetRequested` requests access first and `.denied` is a logged no-op.
- Removed Plan 04's `swift run SeshatAppKit` manual-launch runbook; Step 12 is now XCTest-only and Plan 99 remains the first plan that ships `@main`.
- Split old Step 6 into four smaller steps for observation, idempotence, deinit cancellation, and idle-time transcript refresh.
- Added explicit Week 1 non-goals and two mandatory audits: forbidden-duplicate semantics and sibling cross-plan consistency.

## Non-goals for Week 1
- no global hotkey
- no pill overlay
- no paste injection
- no settings window
- no sleep/wake pre-warming
- no runnable `@main`

## Scope Guardrails
- Observe only the shared `SessionCoordinator.stateStream()` and `SessionCoordinator.lastResult()` APIs from Plan 00.
- Never define a second `SessionState`, `SessionCoordinator`, `TranscriptionResult`, `MicrophonePermissionRequesting`, or `SeshatLogger`.
- Never create `Sources/SeshatAppKit/Composition/AppComposition.swift`; that file remains Plan 99 scope.
- Never import `SeshatAudio` or `SeshatTranscription` from Plan 04 production sources.
- Keep all UI-facing declarations on `@MainActor`.
- Use `SeshatLogger(category: SeshatLogCategory.ui)` for UI and lifecycle logs.
- Do not add a wrapper protocol such as `SessionObserving`, `SessionCoordinating`, or an async-closure façade around the coordinator.
- Tests target pure helpers and `MenuBarSceneModel`; they do not launch `MenuBarExtra` and do not run the executable.

## Planned File Layout
```text
Sources/SeshatAppKit/
  SeshatApp.swift
  Permissions/
    AppKitMicrophonePermissionRequester.swift
  MenuBar/
    MicrophonePermissionState.swift
    MenuBarStatusIcon.swift
    RecordButtonViewModel.swift
    MenuBarSceneModel.swift
    MenuBarScene.swift
    RecordButtonView.swift
Tests/SeshatAppKitTests/
  DevelopmentComposition.swift
  AppKitMicrophonePermissionRequesterTests.swift
  RecordButtonViewModelTests.swift
  MenuBarStatusIconTests.swift
  MenuBarSceneModelTests.swift
  MenuBarFlowIntegrationTests.swift
```

## A. Development-time Composition Choice

### Decision
Choose **Option A** and make it strict.

`SeshatApp` is an injectable shell that receives a shared `SessionCoordinator` plus a `MicrophonePermissionRequesting` conformer. Plan 04 uses that shell only from tests. Plan 99 later provides the real `@main` entrypoint and `AppComposition` wiring.

### Consequence
Plan 04 intentionally does **not** provide a zero-argument executable entrypoint. That is not a missing detail; it is the contract choice that keeps Plan 04 from shipping temporary fake wiring that Plan 99 would have to delete.

The result is:
- Plan 04 owns the menu bar scene, permission requester, pure helper types, and model-level tests.
- Plan 99 owns `Sources/SeshatAppKit/Composition/AppComposition.swift`, production dependency assembly, and the first runnable app entrypoint.

### Test-only `DevelopmentComposition` Shape
This helper lives only in `Tests/SeshatAppKitTests/DevelopmentComposition.swift` and only constructs a real coordinator from Plan 00's shared fakes.

```swift
import Foundation
import SeshatCore
import SeshatSession
import SeshatTestSupport

@MainActor
enum DevelopmentComposition {
    static func makeTestingSessionCoordinator(
        buffers: [PCMBuffer] = [],
        result: TranscriptionResult,
        captureError: SeshatError? = nil,
        transcribeError: SeshatError? = nil,
        logger: SeshatLogger = SeshatLogger(category: SeshatLogCategory.ui)
    ) -> SessionCoordinator
}
```

Important rule:
- `DevelopmentComposition` is test-only and never imported by production `Sources/SeshatAppKit/`.
- It is not a second composition root.
- It does not construct `AVAudioCaptureService` or `FluidAudioTranscriber`.

### Why the coordinator is injected directly
Plan 00 C.3 declares:

```swift
public actor SessionCoordinator {
    public func stateStream() -> AsyncStream<SessionState>
    public func lastResult() -> TranscriptionResult?
}
```

Both methods are actor-isolated. External callers must use:

```swift
let stream = await coordinator.stateStream()
let last = await coordinator.lastResult()
```

That makes the v1 seam invalid:

```swift
stateStream: @escaping @Sendable () -> AsyncStream<SessionState>
```

That sync closure cannot call the actor method without inventing another async wrapper or shadow abstraction, which Plan 00 D.7 forbids. The clean fix is to inject `SessionCoordinator` directly into `MenuBarSceneModel`.

### Plan 99 integration note
Plan 99 should be able to call the app shell exactly like this:

```swift
SeshatApp(
    coordinator: AppComposition.sessionCoordinator,
    permissionRequester: AppComposition.makeMicrophonePermissionRequester()
)
```

Plan 04 therefore keeps `SeshatApp` injectable and keeps every production dependency explicit, but it does not add `@main`.

## B. Planned APIs And View-model Signatures

### `SeshatApp`
```swift
import SwiftUI
import SeshatCore
import SeshatSession

@MainActor
struct SeshatApp: App {
    init(
        coordinator: SessionCoordinator,
        permissionRequester: any MicrophonePermissionRequesting,
        permissionStateProvider: (@MainActor () -> MicrophonePermissionState)? = nil,
        logger: SeshatLogger = SeshatLogger(category: SeshatLogCategory.ui)
    )

    var body: some Scene { get }
}
```

Notes:
- There is no `@main` declaration in Plan 04.
- The optional `permissionStateProvider` exists only to make tests deterministic; production Plan 99 can call the two required parameters only.
- If no provider is supplied, the shell may derive initial state from `AppKitMicrophonePermissionRequester.currentState()` when the concrete requester is available, else default to `.notYetRequested`.

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
import SeshatCore

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

Behavior rules:
- `requestAccess()` matches Plan 00 C.2 exactly: `async -> Bool`.
- `currentState()` is an app-layer helper for UI bootstrapping and is not part of the shared protocol.
- `.restricted` maps to `.denied` at the UI layer.

### `RecordButtonViewModel`
```swift
import Foundation
import SeshatCore

@MainActor
struct RecordButtonViewModel: Equatable {
    let title: String
    let systemImageName: String
    let isEnabled: Bool
    let usesDestructiveRole: Bool

    static func make(from sessionState: SessionState) -> RecordButtonViewModel
}
```

Recommended mapping:
- `.idle` -> `Record`, `mic.circle.fill`, enabled, not destructive
- `.recording` -> `Stop`, `stop.circle.fill`, enabled, destructive
- `.transcribing` -> `Transcribing…`, `waveform.circle.fill`, disabled, not destructive
- `.error` -> `Record Again`, `arrow.clockwise.circle.fill`, enabled, not destructive

### `MenuBarSceneModel`
```swift
import Foundation
import SeshatCore
import SeshatSession

@MainActor
final class MenuBarSceneModel: ObservableObject {
    @Published var state: SessionState = .idle
    @Published var permissionState: MicrophonePermissionState
    @Published var lastResultText: String? = nil

    init(
        coordinator: SessionCoordinator,
        permissionRequester: any MicrophonePermissionRequesting,
        permissionStateProvider: @escaping @MainActor () -> MicrophonePermissionState,
        clipboardWriter: @escaping @MainActor (String) -> Void,
        openSettings: @escaping @MainActor () -> Void,
        logger: SeshatLogger = SeshatLogger(category: SeshatLogCategory.ui)
    )

    var statusIcon: MenuBarStatusIcon { get }
    var recordButton: RecordButtonViewModel { get }

    func startObserving()
    func handleRecordButtonTap() async
    func copyLatestTranscript()
    func openMicrophonePrivacySettings()
}
```

Core observation-loop excerpt (illustrative; the real type also stores permission and UI closures listed above):

```swift
@MainActor
final class MenuBarSceneModel: ObservableObject {
    @Published var state: SessionState = .idle
    @Published var lastResultText: String? = nil

    private let coordinator: SessionCoordinator
    private var observationTask: Task<Void, Never>?

    init(coordinator: SessionCoordinator) {
        self.coordinator = coordinator
    }

    func startObserving() {
        guard observationTask == nil else { return }
        observationTask = Task { [weak self] in
            guard let self else { return }
            let stream = await coordinator.stateStream()
            for await newState in stream {
                await MainActor.run { self.state = newState }
                if case .idle = newState {
                    let last = await coordinator.lastResult()
                    await MainActor.run { self.lastResultText = last?.text }
                }
            }
        }
    }

    deinit { observationTask?.cancel() }
}
```

The real implementation adds:
- stored `permissionRequester`
- stored `permissionStateProvider`
- stored `clipboardWriter`
- stored `openSettings`
- UI logging through `SeshatLogger(category: SeshatLogCategory.ui)`

The permission gate lives inside `handleRecordButtonTap()`:

```swift
func handleRecordButtonTap() async {
    switch permissionState {
    case .granted:
        await coordinator.toggle()
    case .notYetRequested:
        let granted = await permissionRequester.requestAccess()
        permissionState = granted ? .granted : .denied
        if granted {
            await coordinator.toggle()
        }
    case .denied:
        logger.info("Record button tapped while permission denied; ignoring.")
    }
}
```

Rules:
- do not mutate `state` optimistically
- the UI changes recording state only through `stateStream()`
- `.denied` is a no-op here because the scene shows a settings button instead of a record button
- `permissionState` remains app-owned UI state, not a replacement for `SessionState`

### `MenuBarStatusIcon`
```swift
import Foundation
import SeshatCore

@MainActor
struct MenuBarStatusIcon: Equatable {
    let systemImageName: String
    let accessibilityLabel: String
    let showsActiveAccent: Bool

    static func make(
        sessionState: SessionState,
        permissionState: MicrophonePermissionState
    ) -> MenuBarStatusIcon
}
```

Recommended mapping:
- denied -> `mic.slash`, `"Microphone permission denied"`, no active accent
- granted + idle -> `mic`, `"Idle"`, no active accent
- granted + recording -> `mic.fill`, `"Recording"`, active accent
- granted + transcribing -> `mic.fill`, `"Transcribing"`, active accent
- granted + error -> `mic`, `"Error"`, no active accent
- not-yet-requested + idle -> `mic`, `"Permission not requested"`, no active accent

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

### Minimal real SwiftUI snippets
`MenuBarScene`:

```swift
import SwiftUI
import SeshatCore

@MainActor
struct MenuBarScene: View {
    @ObservedObject var model: MenuBarSceneModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Seshat")
                .font(.headline)

            Text(stateLabel(for: model.state))
                .font(.subheadline)
                .foregroundStyle(.secondary)

            switch model.permissionState {
            case .granted:
                RecordButtonView(
                    viewModel: model.recordButton,
                    action: model.handleRecordButtonTap
                )
            case .notYetRequested:
                Button("Grant microphone access") {
                    Task { await model.handleRecordButtonTap() }
                }

                Text("Recording starts immediately after access is granted.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            case .denied:
                Button("Open System Settings") {
                    model.openMicrophonePrivacySettings()
                }

                Text("Microphone access is denied. Enable it in Privacy → Microphone.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if let lastResultText = model.lastResultText, !lastResultText.isEmpty {
                Text(lastResultText)
                    .font(.body)

                Button("Copy Last Transcript") {
                    model.copyLatestTranscript()
                }
            }
        }
        .padding(14)
        .frame(minWidth: 280)
        .task { model.startObserving() }
    }

    private func stateLabel(for state: SessionState) -> String {
        switch state {
        case .idle:
            return "Idle"
        case .recording:
            return "Recording"
        case .transcribing:
            return "Transcribing"
        case .error:
            return "Error"
        }
    }
}
```

`SeshatApp`:

```swift
import AppKit
import SwiftUI
import SeshatCore
import SeshatSession

@MainActor
struct SeshatApp: App {
    @StateObject private var model: MenuBarSceneModel

    init(
        coordinator: SessionCoordinator,
        permissionRequester: any MicrophonePermissionRequesting,
        permissionStateProvider: (@MainActor () -> MicrophonePermissionState)? = nil,
        logger: SeshatLogger = SeshatLogger(category: SeshatLogCategory.ui)
    ) {
        let initialState: MicrophonePermissionState
        if let permissionStateProvider {
            initialState = permissionStateProvider()
        } else if let requester = permissionRequester as? AppKitMicrophonePermissionRequester {
            initialState = requester.currentState()
        } else {
            initialState = .notYetRequested
        }

        _model = StateObject(
            wrappedValue: MenuBarSceneModel(
                coordinator: coordinator,
                permissionRequester: permissionRequester,
                permissionStateProvider: { initialState },
                clipboardWriter: { text in
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(text, forType: .string)
                },
                openSettings: {
                    guard let url = URL(
                        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
                    ) else {
                        return
                    }
                    NSWorkspace.shared.open(url)
                },
                logger: logger
            )
        )
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarScene(model: model)
        } label: {
            Image(systemName: model.statusIcon.systemImageName)
                .accessibilityLabel(model.statusIcon.accessibilityLabel)
        }
    }
}
```

## C. Task Breakdown

Each step is one red-green-refactor cycle with one commit. Keep each iteration narrow and use the smallest relevant `swift test --filter ...` command first.

### Step 1. `AppKitMicrophonePermissionRequester` scaffold + compile
Goal:
- add the production requester in `Sources/SeshatAppKit/Permissions/`
- prove it conforms to `MicrophonePermissionRequesting`

Files:
- `Sources/SeshatAppKit/Permissions/AppKitMicrophonePermissionRequester.swift`
- `Tests/SeshatAppKitTests/AppKitMicrophonePermissionRequesterTests.swift`

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

Pass: `swift test --filter AppKitMicrophonePermissionRequesterTests/testRequesterConformsToSharedProtocol`
Commit: `git commit -m "plan-04 step 1: scaffold microphone permission requester"`

### Step 2. Permission states and cached-decision behavior
Goal:
- introduce the three-state permission UI model
- make `requestAccess()` and `currentState()` agree on cached decisions

Files:
- `Sources/SeshatAppKit/MenuBar/MicrophonePermissionState.swift`
- `Sources/SeshatAppKit/Permissions/AppKitMicrophonePermissionRequester.swift`
- `Tests/SeshatAppKitTests/AppKitMicrophonePermissionRequesterTests.swift`

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

Pass: `swift test --filter AppKitMicrophonePermissionRequesterTests`
Commit: `git commit -m "plan-04 step 2: add microphone permission state machine"`

### Step 3. `MenuBarSceneModel` scaffold and initial permission bootstrap
Goal:
- add the coordinator-direct scene model
- make initial `permissionState` come from an app-layer provider
- prove denied prompt results become `.denied` without touching session state

Files:
- `Sources/SeshatAppKit/MenuBar/MenuBarSceneModel.swift`
- `Tests/SeshatAppKitTests/MenuBarSceneModelTests.swift`

Red:
- `testInitSeedsPermissionStateFromProvider`
- `testRequestingAccessUpdatesPermissionStateToDeniedWhenPromptReturnsFalse`

Green:
- add `MenuBarSceneModel`
- inject `coordinator`, `permissionRequester`, and `permissionStateProvider`
- initialize `permissionState` from the provider
- implement the `.notYetRequested` branch inside `handleRecordButtonTap()`

Behavior:
- log the tap
- await `permissionRequester.requestAccess()`
- update `permissionState` to `.granted` or `.denied`
- leave `sessionState` untouched

Important rule:
- permission state is separate from session state
- this is allowed because it is app-owned UI state, not a second recording state machine

Pass: `swift test --filter MenuBarSceneModelTests/testInitSeedsPermissionStateFromProvider`
Pass: `swift test --filter MenuBarSceneModelTests/testRequestingAccessUpdatesPermissionStateToDeniedWhenPromptReturnsFalse`
Commit: `git commit -m "plan-04 step 3: scaffold coordinator-direct scene model"`

### Step 4. `RecordButtonViewModel` pure derivation
Goal:
- factor button title, icon, tint token, and enabled state into a pure helper

Files:
- `Sources/SeshatAppKit/MenuBar/RecordButtonViewModel.swift`
- `Tests/SeshatAppKitTests/RecordButtonViewModelTests.swift`

Red:
- `testIdleStateMapsToRecordButton`
- `testRecordingStateMapsToStopButton`
- `testTranscribingStateMapsToBusyDisabledButton`
- `testErrorStateMapsToRecordAgainButton`

Green:
- add `RecordButtonViewModel.make(from:)`

Recommended mapping:
- `.idle` -> `Record`, `mic.circle.fill`, enabled, non-destructive
- `.recording` -> `Stop`, `stop.circle.fill`, enabled, destructive
- `.transcribing` -> `Transcribing…`, `waveform.circle.fill`, disabled, non-destructive
- `.error` -> `Record Again`, `arrow.clockwise.circle.fill`, enabled, non-destructive

Refactor:
- keep this free of permission knowledge
- keep this free of AppKit types

Pass: `swift test --filter RecordButtonViewModelTests`
Commit: `git commit -m "plan-04 step 4: add record button view model"`

### Step 5. Permission-gated record action
Goal:
- ensure the UI action respects app-owned microphone permission
- reach `SessionCoordinator.toggle()` only when permission is granted now or becomes granted after prompt

Files:
- `Sources/SeshatAppKit/MenuBar/MenuBarSceneModel.swift`
- `Sources/SeshatAppKit/MenuBar/RecordButtonView.swift`
- `Tests/SeshatAppKitTests/MenuBarSceneModelTests.swift`

Red:
- `testHandleRecordButtonTapTogglesWhenPermissionAlreadyGranted`
- `testHandleRecordButtonTapRequestsAccessThenTogglesWhenPromptSucceeds`
- `testHandleRecordButtonTapDoesNotToggleWhenPromptReturnsFalse`
- `testHandleRecordButtonTapDoesNothingWhenPermissionDenied`

Green:
- add `handleRecordButtonTap() async`
- implement `RecordButtonView`
- wrap the button action in `Task { await action() }`

Rules:
- switch on `permissionState`, not on a second hidden flag
- do not mutate `state` optimistically
- the UI should wait for `stateStream()` to report the real state
- ignored toggles during `.transcribing` must remain the coordinator’s responsibility
- denied taps are logged and ignored
- when `.notYetRequested` is granted, update `permissionState = .granted` before awaiting `coordinator.toggle()`

Pass: `swift test --filter MenuBarSceneModelTests/testHandleRecordButtonTapTogglesWhenPermissionAlreadyGranted`
Pass: `swift test --filter MenuBarSceneModelTests/testHandleRecordButtonTapRequestsAccessThenTogglesWhenPromptSucceeds`
Pass: `swift test --filter MenuBarSceneModelTests/testHandleRecordButtonTapDoesNotToggleWhenPromptReturnsFalse`
Pass: `swift test --filter MenuBarSceneModelTests/testHandleRecordButtonTapDoesNothingWhenPermissionDenied`
Commit: `git commit -m "plan-04 step 5: gate record action on permission state"`

### Step 6.1. Observer task subscribes to `await coordinator.stateStream()` and updates `state`
Goal:
- mirror the authoritative session actor into app-owned published UI state
- prove the model observes the real coordinator API, not a shadow closure

Files:
- `Sources/SeshatAppKit/MenuBar/MenuBarSceneModel.swift`
- `Tests/SeshatAppKitTests/MenuBarSceneModelTests.swift`

Red:
- `testStartObservingPublishesRecordingAfterCoordinatorToggle`
- setup uses a real `SessionCoordinator` built from `FakeAudioCapturing` + `FakeTranscriber`

Green:
- implement `startObserving()`
- call `let stream = await coordinator.stateStream()`
- loop `for await newState in stream`
- assign the new state on the main actor

Required loop:

```swift
observationTask = Task { [weak self] in
    guard let self else { return }
    let stream = await coordinator.stateStream()
    for await newState in stream {
        await MainActor.run { self.state = newState }
    }
}
```

Verification pattern:
1. create the model with a real fake-backed coordinator
2. call `startObserving()`
3. call `await coordinator.toggle()`
4. await a published value change to `.recording`

Pass: `swift test --filter MenuBarSceneModelTests/testStartObservingPublishesRecordingAfterCoordinatorToggle`
Commit: `git commit -m "plan-04 step 6.1: observe coordinator state stream"`

### Step 6.2. `startObserving()` is idempotent
Goal:
- prove repeated calls do not leak duplicate observation tasks

Files:
- `Sources/SeshatAppKit/MenuBar/MenuBarSceneModel.swift`
- `Tests/SeshatAppKitTests/MenuBarSceneModelTests.swift`

Red:
- `testStartObservingIsIdempotent`

Green:
- keep `guard observationTask == nil else { return }`
- if direct assertion is awkward, add an internal optional test hook or internal task-creation counter
- do not add a coordinator wrapper just to observe idempotence

Verification options:
- preferred: task-creation counter increments once even when `startObserving()` is called twice
- fallback: repeated lifecycle-style calls still produce one update sequence per coordinator transition

Pass: `swift test --filter MenuBarSceneModelTests/testStartObservingIsIdempotent`
Commit: `git commit -m "plan-04 step 6.2: make observation start idempotent"`

### Step 6.3. Observation task is cancelled on deinit
Goal:
- avoid leaving background observation work alive after the model is released

Files:
- `Sources/SeshatAppKit/MenuBar/MenuBarSceneModel.swift`
- `Tests/SeshatAppKitTests/MenuBarSceneModelTests.swift`

Red:
- `testDeinitCancelsObservationTask`

Green:
- implement `deinit { observationTask?.cancel() }`
- if needed, use an internal optional cancellation hook for deterministic verification
- keep the cancellation ownership inside the model

Pass: `swift test --filter MenuBarSceneModelTests/testDeinitCancelsObservationTask`
Commit: `git commit -m "plan-04 step 6.3: cancel observation task on deinit"`

### Step 6.4. Idle transitions refresh `lastResultText` from `await coordinator.lastResult()`
Goal:
- keep transcript display sourced from the actor-owned result
- refresh the text when the state machine returns to `.idle`

Files:
- `Sources/SeshatAppKit/MenuBar/MenuBarSceneModel.swift`
- `Tests/SeshatAppKitTests/MenuBarSceneModelTests.swift`

Red:
- `testIdleTransitionRefreshesLastResultTextFromCoordinator`

Green:
- on every `.idle` state observed from the stream, call `await coordinator.lastResult()`
- store `lastResultText = last?.text`
- do not add a duplicated cached result store outside the coordinator contract

Reason:
- the session actor owns the authoritative latest `TranscriptionResult`
- the menu bar popover only mirrors `text`

Pass: `swift test --filter MenuBarSceneModelTests/testIdleTransitionRefreshesLastResultTextFromCoordinator`
Commit: `git commit -m "plan-04 step 6.4: refresh transcript text on idle"`

### Step 7. Copy-to-clipboard behavior
Goal:
- copy the latest transcript text with one click
- keep clipboard scope narrow for Week 1

Files:
- `Sources/SeshatAppKit/MenuBar/MenuBarSceneModel.swift`
- `Tests/SeshatAppKitTests/MenuBarSceneModelTests.swift`

Red:
- `testCopyLatestTranscriptWritesCurrentTranscriptToClipboard`
- `testCopyLatestTranscriptDoesNothingWhenTranscriptIsMissing`

Green:
- add `copyLatestTranscript()`
- inject `clipboardWriter`
- call the closure only when `lastResultText` is present and non-empty

Rules:
- Week 1 writes the plain string directly to `NSPasteboard.general`
- full clipboard save/restore remains Week 2 scope
- do not log transcript contents

Pass: `swift test --filter MenuBarSceneModelTests/testCopyLatestTranscriptWritesCurrentTranscriptToClipboard`
Pass: `swift test --filter MenuBarSceneModelTests/testCopyLatestTranscriptDoesNothingWhenTranscriptIsMissing`
Commit: `git commit -m "plan-04 step 7: add transcript copy action"`

### Step 8. Permission-specific scene affordances and settings deep link
Goal:
- render the correct primary CTA for each permission state
- deep-link denied users to microphone privacy settings
- keep the denied settings affordance in place of the record button, not alongside it

Files:
- `Sources/SeshatAppKit/MenuBar/MenuBarScene.swift`
- `Sources/SeshatAppKit/MenuBar/MenuBarSceneModel.swift`
- `Tests/SeshatAppKitTests/MenuBarSceneModelTests.swift`

Red:
- `testOpenMicrophonePrivacySettingsInvokesInjectedSettingsAction`
- `testGrantedPermissionShowsRecordButtonModel`
- `testNotYetRequestedPermissionShowsGrantPrimaryCTA`
- `testDeniedPermissionShowsSettingsPrimaryCTA`

Green:
- add `openMicrophonePrivacySettings()`
- inject `openSettings`
- implement the scene switch:
  - `.granted` -> render `RecordButtonView`
  - `.notYetRequested` -> render `Grant microphone access`
  - `.denied` -> render `Open System Settings`
- add the note that recording starts after grant
- add the denied explanatory note about Privacy → Microphone

Pass: `swift test --filter MenuBarSceneModelTests/testOpenMicrophonePrivacySettingsInvokesInjectedSettingsAction`
Pass: `swift test --filter MenuBarSceneModelTests/testGrantedPermissionShowsRecordButtonModel`
Pass: `swift test --filter MenuBarSceneModelTests/testNotYetRequestedPermissionShowsGrantPrimaryCTA`
Pass: `swift test --filter MenuBarSceneModelTests/testDeniedPermissionShowsSettingsPrimaryCTA`
Commit: `git commit -m "plan-04 step 8: add permission-specific scene affordances"`

### Step 9. Menu bar glyph selection logic
Goal:
- keep status-icon choice pure and unit-testable

Files:
- `Sources/SeshatAppKit/MenuBar/MenuBarStatusIcon.swift`
- `Tests/SeshatAppKitTests/MenuBarStatusIconTests.swift`

Red:
- `testGrantedIdleMapsToMic`
- `testGrantedRecordingMapsToFilledMicWithActiveAccent`
- `testDeniedAlwaysMapsToMicSlash`

Green:
- add `MenuBarStatusIcon.make(sessionState:permissionState:)`

Mapping:
- denied -> `mic.slash`, `"Microphone permission denied"`, inactive
- granted + idle -> `mic`, `"Idle"`, inactive
- granted + recording -> `mic.fill`, `"Recording"`, active
- granted + transcribing -> `mic.fill`, `"Transcribing"`, active
- granted + error -> `mic`, `"Error"`, inactive
- not-yet-requested + idle -> `mic`, `"Permission not requested"`, inactive

Rule:
- the pure function is the tested source of truth
- SwiftUI adapts it into the `MenuBarExtra` label later

Pass: `swift test --filter MenuBarStatusIconTests`
Commit: `git commit -m "plan-04 step 9: add menu bar icon mapping"`

### Step 10. `SeshatApp` injectable shell without `@main`
Goal:
- ship the production app-shell type that Plan 99 can instantiate
- keep bootstrap explicit without declaring a runnable entrypoint

Files:
- `Sources/SeshatAppKit/SeshatApp.swift`
- `Tests/SeshatAppKitTests/MenuBarSceneModelTests.swift`

Red:
- `testCanInstantiateSeshatAppWithCoordinatorAndPermissionRequester`

Green:
- add `SeshatApp: App`
- own one `@StateObject` scene model
- expose a `MenuBarExtra`
- source the status item image from `model.statusIcon`
- wire `NSPasteboard.general` and `NSWorkspace.shared.open(_:)` closures here

Rules:
- do not add `@main`
- do not add `AppDelegate`
- do not prewarm models on launch
- do not auto-prompt for permission on launch
- accept `coordinator:` and `permissionRequester:` exactly so Plan 99 Step 3 can call the shell directly

Pass: `swift test --filter MenuBarSceneModelTests/testCanInstantiateSeshatAppWithCoordinatorAndPermissionRequester`
Commit: `git commit -m "plan-04 step 10: add injectable app shell without main"`

### Step 11. Add `DevelopmentComposition` test helper
Goal:
- centralize real fake-backed coordinator construction for `SeshatAppKitTests`
- keep production sources free of test-only wiring

Files:
- `Tests/SeshatAppKitTests/DevelopmentComposition.swift`
- `Tests/SeshatAppKitTests/MenuBarFlowIntegrationTests.swift`

Red:
- `testDevelopmentCompositionCreatesIdleTestingCoordinator`

Green:
- add `DevelopmentComposition.makeTestingSessionCoordinator(...)`
- build a real `SessionCoordinator` from `FakeAudioCapturing` + `FakeTranscriber`
- keep the file under `Tests/SeshatAppKitTests/` only

Rules:
- no fake coordinator type
- no production imports of `SeshatTestSupport`
- default the helper to a deterministic fake result for integration tests

Pass: `swift test --filter MenuBarFlowIntegrationTests/testDevelopmentCompositionCreatesIdleTestingCoordinator`
Commit: `git commit -m "plan-04 step 11: add test-only development composition"`

### Step 12. XCTest-only integration verification
Goal:
- verify the full Week 1 menu-layer flow without launching the executable
- prove the coordinator-direct scene model works with Plan 00 shared fakes

Files:
- `Tests/SeshatAppKitTests/MenuBarFlowIntegrationTests.swift`

Red:
- `testRecordStopTranscribeIdleFlowPublishesLatestResult`

Exact flow:
1. build `testCoordinator = DevelopmentComposition.makeTestingSessionCoordinator(...)`
2. create `MenuBarSceneModel(coordinator: testCoordinator, ...)`
3. call `startObserving()`
4. set `permissionState = .granted` through the deterministic test provider
5. call `await model.handleRecordButtonTap()` and observe `.recording`
6. call `await model.handleRecordButtonTap()` again and observe `.transcribing`
7. await the final `.idle`
8. assert `model.lastResultText == fakeResult.text`

Green:
- use only `FakeAudioCapturing` and `FakeTranscriber` from `SeshatTestSupport`
- prefer awaiting published values or a small async helper over arbitrary sleeps
- keep the test at the view-model level

Prohibited in Step 12:
- no `swift run SeshatAppKit`
- no `MenuBarExtra` launch
- no temporary `@main`
- no production `AppComposition`

Pass: `swift test --filter MenuBarFlowIntegrationTests/testRecordStopTranscribeIdleFlowPublishesLatestResult`
Commit: `git commit -m "plan-04 step 12: add xctest-only menu flow verification"`

## D. Handoff Signals
- Plan 04 does NOT ship a runnable `@main`. Production `@main` is Plan 99's responsibility. Plan 04 tests verify all UI logic at the view-model level.
- `SeshatAppKit` builds with the injectable app shell, permission requester, menu bar scene model, and popover views.
- `AppKitMicrophonePermissionRequester` conforms to `MicrophonePermissionRequesting`.
- Permission state is exactly three app-owned UI states: not-yet-requested, granted, denied.
- `MenuBarSceneModel` observes `await coordinator.stateStream()` directly and uses `await coordinator.lastResult()` on idle transitions.
- The record path requests permission first when needed and never routes around app-owned permission flow.
- Copy uses `NSPasteboard.general` directly and does not attempt save/restore.
- Denied permission exposes `Open System Settings`, and that button appears in place of the record button.
- Status icon selection is covered by pure unit tests.
- Integration coverage uses a real `SessionCoordinator` built from `FakeAudioCapturing` and `FakeTranscriber`.
- No `SeshatAppKit` source outside future `Composition/` imports `SeshatAudio` or `SeshatTranscription`.
- No file exists at `Sources/SeshatAppKit/Composition/AppComposition.swift`.

Plan 99 then only needs to create `AppComposition.swift`, wire the single production `SessionCoordinator`, and add the first real `@main` bootstrap that injects into `SeshatApp`.

## E. Dependency Table

### Parallel groups
| Group | Steps | Reason |
|---|---|---|
| A | 1, 4, 9 | requester scaffold, record-button derivation, and icon derivation are independent |
| B | 2, 7 | permission-state mapping and copy behavior are independent once base files exist |
| C | 3, 5, 6.1, 6.2, 6.3, 6.4 | same scene-model file; keep one implementer on the critical path |
| D | 8, 10 | scene rendering and shell wiring can proceed after the model is stable |
| E | 11, 12 | integration helper and integration verification land last |

### Strict dependencies
| Step | Depends on | Why |
|---|---|---|
| 1 | Plan 01 | target and test scaffold must exist |
| 2 | 1 | requester must exist before state mapping tests |
| 3 | 2 | model needs the permission state concept and requester behavior |
| 4 | Plan 00 | only shared `SessionState` is needed |
| 5 | 3, 4 | action logic needs model plus button model |
| 6.1 | 3 | observation lives in the model |
| 6.2 | 6.1 | idempotence only makes sense after observation exists |
| 6.3 | 6.1 | cancellation only makes sense after observation exists |
| 6.4 | 6.1 | idle refresh depends on the observation loop |
| 7 | 6.4 | copy behavior depends on transcript state existing |
| 8 | 3, 5 | permission CTA rendering depends on the permission-aware model |
| 9 | 2, 4 | icon derivation depends on permission and session state |
| 10 | 3, 8, 9 | shell should consume the stable model, scene, and icon mapping |
| 11 | Plan 00 | helper uses shared fakes and real coordinator |
| 12 | 5, 6.1, 6.4, 11 | integration flow needs permission gate, observation, last-result refresh, and helper |

## F. Logging Plan
Use `SeshatLogger(category: SeshatLogCategory.ui)` for:
- observation start
- duplicate-observer suppression
- record-button taps
- permission request results
- denied no-op taps
- copy-button actions
- settings-opening actions

Do not use `print()`. Do not log transcript contents. Do not add logger categories outside Plan 00's shared logger surface.

## Forbidden Duplicates Semantic Audit
| Declaration | Could be mistaken for | Why it is NOT a duplicate |
|---|---|---|
| `AppKitMicrophonePermissionRequester` | `MicrophonePermissionRequesting` | Concrete macOS conformer for the shared protocol. Plan 00 owns the protocol; Plan 04 owns the executable-target bridge to `AVCaptureDevice`. |
| `MicrophonePermissionState` | `SessionState` | UI-only permission-flow state. It answers whether the app may request/use the mic; it is not the recording/transcribing state machine. `SessionState.recording` and `MicrophonePermissionState.denied` describe different axes. |
| `RecordButtonViewModel` | `SessionState` | Pure projection for button copy/icon/enablement. No state machine, no permission ownership, no side effects. |
| `MenuBarSceneModel` | `SessionCoordinator` | Main-actor UI adapter that observes the actor and exposes published values. It does not replace the coordinator and v2 injects the real actor directly. |
| `MenuBarStatusIcon` | `SessionState` | Pure UI projection from session + permission state into status-item display data. |
| `MenuBarScene` | none in Plan 00 | SwiftUI popover view. Plan 00 defines no view-layer types. |
| `RecordButtonView` | none in Plan 00 | Small rendering helper for `RecordButtonViewModel`; presentation only. |
| `SeshatApp` | `AppComposition` | Injectable app shell, not a composition root. `AppComposition` creates dependencies; `SeshatApp` consumes them. No `@main` here. |
| `DevelopmentComposition` | `AppComposition` | Test-only helper in `Tests/SeshatAppKitTests/` that builds a real coordinator from `FakeAudioCapturing` + `FakeTranscriber`. Never imported by production code. |

Specific audits requested by review:
- `MicrophonePermissionState` is not a duplicate of `SessionState`; it models permission flow, not the session actor state machine.
- `DevelopmentComposition` is not a duplicate of `AppComposition`; it is test-only, fake-backed, and lives only under `Tests/SeshatAppKitTests/`.
- `SeshatApp` is not a duplicate of any Plan 00 type; it is an injectable shell, not a production dependency factory.

Redesign applied in v2 to avoid duplicate-smelling surface:
- Removed `AppDelegate`.
- Removed `LastResultView`.
- Removed extra tint enums.

## Sibling Cross-Plan Audit
- Plan 00 C.3 `stateStream()` actor method: confirmed. v2 uses `await coordinator.stateStream()`, not a sync closure.
- Plan 00 C.3 `lastResult()` actor method: confirmed. v2 uses `await coordinator.lastResult()` on idle transitions.
- Plan 00 C.2 `requestAccess() async -> Bool`: confirmed. `AppKitMicrophonePermissionRequester` keeps that exact signature.
- Plan 99 Step 3 / Step 5 expect Option A shell injection: confirmed. `SeshatApp` keeps `coordinator:` and `permissionRequester:` as the required parameters.
- Plan 99 does not expect Plan 04 to ship `@main`: confirmed. v2 forbids `@main` in `Sources/SeshatAppKit/`.
- Plan 02 / Plan 03 ownership boundary: confirmed. No `SeshatAudio` or `SeshatTranscription` imports in Plan 04 production sources; test-only `DevelopmentComposition` uses `SeshatTestSupport` fakes.
- Sibling mismatch result: none blocking. The only nuance is the optional test helper parameter on `SeshatApp`, which defaults away and does not affect Plan 99's call site.

## Self-verification Checklist
- [x] stateStream seam uses `await coordinator.stateStream()`, not a sync closure
- [x] Record button path gates on permission state
- [x] No `@main` declared in any Sources file
- [x] `swift run SeshatAppKit` runbook moved to Plan 99, not Plan 04
- [x] `Sources/SeshatAppKit/Composition/AppComposition.swift` is NOT created
- [x] No `import SeshatAudio` / `import SeshatTranscription` anywhere in Plan 04 Sources
- [x] No `print()`; all UI logs via `SeshatLogger(category: SeshatLogCategory.ui)`
- [x] `MicrophonePermissionState` is UI-only, not confused with `SessionState`
- [x] Step 6 split into 6.1–6.4 granularity
- [x] `DevelopmentComposition` lives only in `Tests/SeshatAppKitTests/`

## G. Open Questions
1. Whether `MenuBarExtra` will reliably show accent/destructive tint in the status item depends on macOS behavior; the plan treats glyph choice and accessibility label as the stable contract and active accent as best-effort.
2. The exact helper used in tests to await `@Published` transitions can be a small local XCTest utility or Combine-based recorder. Either is fine as long as tests avoid arbitrary sleeps.
3. If a deterministic assertion for deinit cancellation is awkward, use an internal optional cancellation hook on the model rather than inventing a coordinator wrapper or second observer abstraction.

## H. Completion Definition
Plan 04 v2 is complete when:
- the app shell and menu bar popover exist in `SeshatAppKit` without `@main`
- permission prompting is production-backed by AVFoundation in `SeshatAppKit/Permissions/`
- UI state is derived from shared contract types and app-owned permission state only
- `MenuBarSceneModel` observes the real coordinator actor directly
- tests cover button derivation, icon derivation, permission transitions, state observation, idle transcript refresh, copy behavior, and fake-backed integration flow
- the plan leaves no dead-code composition path for Plan 99 to clean up
