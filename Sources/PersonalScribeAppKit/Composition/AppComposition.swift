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

    /// #078.31a — Disk-backed `WorkflowModeStore` for `workflow-modes.json`.
    /// Sits at composition root so the registry, migrator, and any future
    /// Modes-tab editor share the same persistence seam.
    public static let workflowModeStore: any WorkflowModeStoring = WorkflowModeStore()

    /// #078.31a — Registry feeding the active workflow mode + custom-mode list.
    /// Replaces `ServiceBackedActiveModeProvider` as the source of truth for
    /// active-mode state (per L21). `availableKindsProvider` queries
    /// `ActiveModelService` for the kinds with active descriptors so the
    /// validator can reject modes whose required Kind has no active model.
    public static let workflowModeRegistry: WorkflowModeRegistry = {
        // Initial fix per Phase G runtime crash: SessionCoordinator is
        // an actor (NOT @MainActor), so the registry's
        // availableKindsProvider runs on a non-MainActor context and
        // cannot use `MainActor.assumeIsolated` to reach
        // `modelService.activeDescriptor`. Falling back to "all enabled
        // kinds" (skips the kind-availability rule of validation).
        // Tightening this — passing the actual per-kind active set
        // without the MainActor hop — is filed as a follow-up.
        let kindsProvider: @Sendable () -> Set<ModelKind> = {
            Set(ModelKind.allCases.filter(\.isEnabled))
        }
        do {
            let registry = try WorkflowModeRegistry(
                store: workflowModeStore,
                availableKindsProvider: kindsProvider
            )
            // #089: legacy-toggle migration is no longer needed —
            // GeneralTab toggles write UserDefaults directly and
            // recipes consult them via `Parameter.setting(...)`.
            return registry
        } catch {
            // Fallback: in-memory registry so the app still launches.
            // Logged for diagnosis; built-in dictation still works.
            PersonalScribeLogger(category: PersonalScribeLogCategory.session)
                .error("WorkflowModeRegistry init failed", error: error)
            // swiftlint:disable:next force_try
            return try! WorkflowModeRegistry(
                store: InMemoryWorkflowModeStore(),
                availableKindsProvider: { Set(ModelKind.allCases) }
            )
        }
    }()

    /// #078.31a — typed-accessor processor provider feeds both
    /// `ActiveModelService.download` and the orchestrator's
    /// recipe-driven dispatch (via `RecipeBuilder`, per L24).
    public static let processorProvider: any ModelBoundProcessorProviding = ModelBoundProcessorProvider()

    public static let sessionCoordinator: SessionCoordinator = {
        let logger = PersonalScribeLogger(category: PersonalScribeLogCategory.session)
        let capture = AVAudioCaptureService(
            logger: PersonalScribeLogger(category: PersonalScribeLogCategory.audio),
            inputDeviceProvider: AVFoundationInputDeviceProvider(defaults: .standard),
            shouldMuteOutput: { MuteOutputWhileRecordingPreference.resolve() }
        )

        let coordinator = SessionCoordinator(
            capture: capture,
            modelService: modelService,
            processorProvider: processorProvider,
            logger: logger,
            transcriptRepository: transcriptRepository,
            vadProvider: vadProvider,
            workflowModeRegistry: workflowModeRegistry,
            availableKindsProvider: {
                Set(ModelKind.allCases.filter(\.isEnabled))
            }
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
    public static let hotkeyMonitor: GlobalHotkeyMonitor = makeHotkeyMonitorWithPerModeWiring()

    @MainActor
    private static func makeHotkeyMonitorWithPerModeWiring() -> GlobalHotkeyMonitor {
        let monitor = makeGlobalHotkeyMonitor()
        // #089 L-22 — wire per-mode hotkey activation: set the
        // registry's runtime current mode, then start recording via
        // the same coordinator path the global hotkey uses.
        let registry = workflowModeRegistry
        let coordinator = sessionCoordinator
        monitor.setOnPerModeActivate { modeID in
            registry.setCurrent(id: modeID)
            Task {
                await coordinator.startIfIdle()
            }
        }
        // Seed the per-mode table from the current custom modes.
        monitor.updatePerModeHotkeys(registry.customModes)
        return monitor
    }

    /// #089 — Task that subscribes to the registry's customModesStream
    /// and forwards updates into the hotkey monitor's per-mode table.
    @MainActor
    private static var perModeHotkeyObservationTask: Task<Void, Never>?

    @MainActor
    static func startPerModeHotkeyObservation() {
        guard perModeHotkeyObservationTask == nil else { return }
        let registry = workflowModeRegistry
        let monitor = hotkeyMonitor
        perModeHotkeyObservationTask = Task { @MainActor in
            for await modes in registry.customModesStream() {
                monitor.updatePerModeHotkeys(modes)
            }
        }
    }

    @MainActor
    static func makeStartupCoordinator(
        coordinator: SessionCoordinator = AppComposition.sessionCoordinator,
        hotkeyMonitor: GlobalHotkeyMonitor = AppComposition.hotkeyMonitor
    ) -> AppStartupCoordinator {
        let logger = PersonalScribeLogger(category: PersonalScribeLogCategory.app)

        return AppStartupCoordinator(
            startHotkeyMonitor: {
                hotkeyMonitor.start()
                startPerModeHotkeyObservation()
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

