import AppKit
import Combine
import Foundation
import PersonalScribeAudio
import PersonalScribeCore
import PersonalScribeSession
import PersonalScribeTranscription
import PersonalScribeVAD

@MainActor
public enum AppComposition {
    /// Single shared `AppDatabase` instance per plan §3: "exactly one instance
    /// per app process, held as a shared reference inside `AppComposition` —
    /// never re-constructed by callers." If init fails (disk read-only, path
    /// not writable), the whole persistence surface degrades to nil; callers
    /// treat missing history as "nothing to show" rather than crashing.
    public static let appDatabase: AppDatabase? = {
        let logger = PersonalScribeLogger(category: PersonalScribeLogCategory.session)
        do {
            return try AppDatabase(locator: AppConfig.liveStorageLocator())
        } catch {
            logger.error("AppDatabase init failed; continuing without persistence", error: error)
            return nil
        }
    }()

    /// Shared per-operation observer for database reads/writes (backlog
    /// #043). Injected into `transcriptRepository` below so every repo
    /// call updates `current` on the main actor. Subscribers (future
    /// banner / Advanced row / Settings diagnostics) read this directly.
    public static let databaseOperationObserver: DatabaseOperationObserver = DatabaseOperationObserver()

    /// The single shared `TranscriptRepository` wrapping `appDatabase`. Nil
    /// only when `appDatabase` failed to open.
    public static let transcriptRepository: TranscriptRepository? = {
        guard let appDatabase else { return nil }
        return TranscriptRepository(
            database: appDatabase,
            operationObserver: databaseOperationObserver
        )
    }()

    public static let modelService: ActiveModelService = {
        ActiveModelService(
            logger: PersonalScribeLogger(category: PersonalScribeLogCategory.session)
        )
    }()

    /// Bridge `ActiveModelService.$activeModelIDs` (Combine, MainActor)
    /// to `AppStoreActiveModeProviding` (AsyncStream-based) so the
    /// central `AppStore` can observe active-mode flips. Computed
    /// lazily off the shared `modelService`.
    public static let activeModeProvider: any AppStoreActiveModeProviding = {
        ServiceBackedActiveModeProvider(modelService: modelService)
    }()

    /// VAD provider — nil if the bundled Silero `.mlmodelc` resource failed
    /// to resolve (dev / shipping error). Failure is silent: the orchestrator
    /// treats nil identically to the "feature disabled" path, so recording
    /// still works exactly as it did pre-#046. Not routed through
    /// `SessionState.error` per design lock.
    public static let vadProvider: (any VadProviding)? = {
        let logger = PersonalScribeLogger(category: PersonalScribeLogCategory.session)
        do {
            return try FluidAudioVadProvider()
        } catch {
            logger.error(
                "Bundled VAD model not found; auto-stop silently disabled",
                error: error
            )
            return nil
        }
    }()

    /// VAD preferences reader — UserDefaults-backed snapshot. Orchestrator
    /// calls `current()` once per session start.
    public static let vadPreferences: any VadPreferencesReading = UserDefaultsVadPreferencesReader()

    public static let sessionCoordinator: SessionCoordinator = {
        let logger = PersonalScribeLogger(category: PersonalScribeLogCategory.session)
        let capture = AVAudioCaptureService(
            logger: PersonalScribeLogger(category: PersonalScribeLogCategory.audio),
            inputDeviceProvider: AVFoundationInputDeviceProvider(defaults: .standard),
            shouldMuteOutput: { MuteOutputWhileRecordingPreference.resolve() }
        )
        let transcriberProvider = ModelBoundTranscriberProvider()

        let coordinator = SessionCoordinator(
            capture: capture,
            modelService: modelService,
            transcriberProvider: transcriberProvider,
            logger: logger,
            transcriptRepository: transcriptRepository,
            vadProvider: vadProvider,
            vadPreferences: vadPreferences
        )

        wirePostSetActivePrewarm(modelService: modelService, coordinator: coordinator)

        return coordinator
    }()

    /// Wire `modelService.onSetActive` to `coordinator.prepareTranscriber()`
    /// so an explicit Activate flips the transcriber prep at activate-time.
    /// Pulled out of the `sessionCoordinator` lazy initializer to keep the
    /// closure-isolation chain simple under Swift 6 strict concurrency
    /// (assigning a `@Sendable` closure that awaits an actor inside a
    /// MainActor static-let initializer trips the "main-actor + actor"
    /// isolation conflict; doing it from a plain function side-steps that).
    private static func wirePostSetActivePrewarm(
        modelService: ActiveModelService,
        coordinator: SessionCoordinator
    ) {
        modelService.onSetActive = { [weak coordinator] in
            do {
                try await coordinator?.prepareTranscriber()
            } catch is CancellationError {
                return
            } catch {
                PersonalScribeLogger(category: PersonalScribeLogCategory.session)
                    .error("Post-setActive prewarm failed", error: error)
            }
        }
    }

    public static func makeSessionCoordinator() -> SessionCoordinator {
        sessionCoordinator
    }

    public static func makeGlobalHotkeyMonitor() -> GlobalHotkeyMonitor {
        makeGlobalHotkeyMonitor(
            permissionService: makePermissionService(),
            coordinator: AppComposition.sessionCoordinator
        )
    }

    /// Build the hotkey monitor wired to the session coordinator.
    ///
    /// The hotkey gestures map to explicit session actions:
    /// * **Tap** (onToggle) → single-tap release starts or stops recording
    ///   via `coordinator.toggle()`.
    /// * **Hold start** (onHoldStart) → 300 ms hold enters
    ///   `.holdRecording` via `coordinator.startHoldIfIdle()`; the
    ///   `AppStore` derives `.holdToRecord` pill visibility through
    ///   `derivePillVisibility`, so no side-channel push is needed.
    /// * **Hold release** (onHoldRelease) → release stops recording via
    ///   `coordinator.stopIfActive()`; the session-state mapping takes
    ///   over and shows `.transcribing`.
    public static func makeGlobalHotkeyMonitor(
        permissionService: any PermissionService,
        coordinator: SessionCoordinator
    ) -> GlobalHotkeyMonitor {
        return GlobalHotkeyMonitor(
            onToggle: {
                Task {
                    await coordinator.toggle()
                }
            },
            onHoldStart: {
                Task {
                    await coordinator.startHoldIfIdle()
                }
            },
            onHoldRelease: {
                Task {
                    await coordinator.stopIfActive()
                }
            },
            permissionService: makePermissionServiceAdapter(wrapping: permissionService)
        )
    }

    @MainActor
    public static let hotkeyMonitor: GlobalHotkeyMonitor = makeGlobalHotkeyMonitor()

    @MainActor
    static func makeStartupCoordinator(
        coordinator: SessionCoordinator = AppComposition.sessionCoordinator,
        hotkeyMonitor: GlobalHotkeyMonitor = AppComposition.hotkeyMonitor
    ) -> AppStartupCoordinator {
        let logger = PersonalScribeLogger(category: PersonalScribeLogCategory.app)

        return AppStartupCoordinator(
            startHotkeyMonitor: {
                hotkeyMonitor.start()
            },
            prepareTranscriber: {
                do {
                    try await coordinator.prepareTranscriber()
                } catch is CancellationError {
                    return
                } catch {
                    logger.error("Startup transcriber preparation failed", error: error)
                }
            },
            logger: logger
        )
    }

    static func makePermissionService() -> AppKitPermissionService {
        AppKitPermissionService()
    }

    private static func makePermissionServiceAdapter(
        wrapping permissionService: any PermissionService
    ) -> PermissionServiceAdapter {
        if let permissionService = permissionService as? PermissionServiceAdapter {
            return permissionService
        }

        return wrapPermissionService(permissionService)
    }

    private static func wrapPermissionService<Service: PermissionService>(
        _ permissionService: Service
    ) -> PermissionServiceAdapter {
        PermissionServiceAdapter(wrapping: permissionService)
    }
}

/// Thin `AppStoreActiveModeProviding` adapter over `ActiveModelService`.
/// Translates the service's per-kind `[ModelKind: String]` map back
/// into a `WorkflowMode?` via the registered `ModeRegistry` — the
/// `AppStore` consumes mode descriptors, not model ids.
///
/// Added in #024.10 alongside the protocol-drop (`ModelService`) and
/// `AppKitActiveModeProvider` deletion. Sits at the AppKit layer so
/// the shared `AppStore` (PersonalScribeCore) doesn't have to depend
/// on `PersonalScribeSession.ActiveModelService`. The struct itself
/// is `Sendable` (lock-protected `StateBox`) — only the `init` runs on
/// `MainActor` because `ActiveModelService` is `MainActor`-isolated.
public struct ServiceBackedActiveModeProvider: AppStoreActiveModeProviding, @unchecked Sendable {
    private let state: StateBox

    @MainActor
    public init(modelService: ActiveModelService) {
        let state = StateBox(
            currentMode: Self.modeDescriptor(for: modelService.activeModelIDs)
        )
        let observation = modelService.$activeModelIDs.sink { [weak state] activeIDs in
            state?.publish(Self.modeDescriptor(for: activeIDs))
        }
        state.storeObservation(observation)
        self.state = state
    }

    public func currentActiveMode() -> WorkflowMode? {
        state.loadCurrentMode()
    }

    public func activeModeStream() -> AsyncStream<WorkflowMode?> {
        let state = self.state
        let id = UUID()

        return AsyncStream { continuation in
            state.register(continuation, id: id)
            continuation.onTermination = { _ in
                state.removeContinuation(id: id)
            }
        }
    }

    /// Match a registered mode by `(voiceModelID, aiModelID)` against
    /// the `.asr` slot in the active-id map. ModeRegistry contains
    /// every mode the user can pick; the active mode is the one whose
    /// voice model id equals the active `.asr` id (and aiModelID is
    /// nil today — modes don't yet pin AI presets).
    private static func modeDescriptor(
        for activeIDs: [ModelKind: String]
    ) -> WorkflowMode? {
        guard let activeASRID = activeIDs[.asr] else { return nil }
        return ModeRegistry.all.first {
            $0.voiceModelID == activeASRID && $0.aiModelID == nil
        }
    }
}

private final class StateBox: @unchecked Sendable {
    private let lock = NSLock()
    private var currentMode: WorkflowMode?
    private var continuations: [UUID: AsyncStream<WorkflowMode?>.Continuation] = [:]
    private var observation: AnyCancellable?

    init(currentMode: WorkflowMode?) {
        self.currentMode = currentMode
    }

    func loadCurrentMode() -> WorkflowMode? {
        lock.lock()
        defer { lock.unlock() }
        return currentMode
    }

    func register(
        _ continuation: AsyncStream<WorkflowMode?>.Continuation,
        id: UUID
    ) {
        lock.lock()
        continuations[id] = continuation
        continuation.yield(currentMode)
        lock.unlock()
    }

    func removeContinuation(id: UUID) {
        lock.lock()
        continuations[id] = nil
        lock.unlock()
    }

    func publish(_ mode: WorkflowMode?) {
        lock.lock()
        currentMode = mode
        for continuation in continuations.values {
            continuation.yield(mode)
        }
        lock.unlock()
    }

    func storeObservation(_ observation: AnyCancellable) {
        lock.lock()
        self.observation = observation
        lock.unlock()
    }

    deinit {
        lock.lock()
        let continuations = Array(continuations.values)
        let observation = self.observation
        lock.unlock()

        observation?.cancel()
        for continuation in continuations {
            continuation.finish()
        }
    }
}
