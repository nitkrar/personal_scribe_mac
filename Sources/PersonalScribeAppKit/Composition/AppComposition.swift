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
    public static let diagnosticsStore = DiagnosticsStore(capacity: 200)

    public static let diagnostics: DiagnosticsReporter = {
        return DiagnosticsReporter(
            sinks: [
                OSLogDiagnosticsSink(),
                ErrorFileDiagnosticsSink(),
                VerboseFileDiagnosticsSink(
                    isEnabled: { DiagnosticLoggingMode.resolve() == .verbose }
                ),
                RingBufferDiagnosticsSink(
                    store: diagnosticsStore,
                    minimumLevelProvider: {
                        DiagnosticLoggingMode.resolve().minimumBufferedLevel
                    }
                ),
            ]
        )
    }()

    public static func makeLogger(_ category: String) -> PersonalScribeLogger {
        PersonalScribeLogger(category: category, reporter: diagnostics)
    }

    /// Single shared `AppDatabase` instance per plan §3: "exactly one instance
    /// per app process, held as a shared reference inside `AppComposition` —
    /// never re-constructed by callers." If init fails (disk read-only, path
    /// not writable), the whole persistence surface degrades to nil; callers
    /// treat missing history as "nothing to show" rather than crashing.
    public static let appDatabase: AppDatabase? = {
        let logger = makeLogger(PersonalScribeLogCategory.session)
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
            operationObserver: databaseOperationObserver,
            logger: makeLogger(PersonalScribeLogCategory.app)
        )
    }()

    public static let modelService: ActiveModelService = {
        ActiveModelService(
            logger: makeLogger(PersonalScribeLogCategory.session)
        )
    }()

    public static let modelLanguagePreference: ModelLanguagePreference = makeModelLanguagePreference()

    static func makeModelLanguagePreference(
        suiteName: String? = nil,
        registeredModels: [ModelDescriptor] = BuiltInModelCatalog.registeredModels,
        logger: PersonalScribeLogger? = nil
    ) -> ModelLanguagePreference {
        ModelLanguagePreference(
            suiteName: suiteName,
            registeredModels: registeredModels,
            logger: logger ?? makeLogger(PersonalScribeLogCategory.app)
        )
    }

    /// VAD provider — nil if the bundled Silero `.mlmodelc` resource failed
    /// to resolve (dev / shipping error). Failure is silent: the orchestrator
    /// treats nil identically to the "feature disabled" path, so recording
    /// still works exactly as it did pre-#046. Not routed through
    /// `SessionState.error` per design lock.
    public static let vadProvider: (any VadProviding)? = {
        let logger = makeLogger(PersonalScribeLogCategory.session)
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
            makeLogger(PersonalScribeLogCategory.session)
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
    public static let processorProvider: any ModelBoundProcessorProviding = ModelBoundProcessorProvider(
        logger: makeLogger(PersonalScribeLogCategory.transcription)
    )

    /// #028 / 5a-v2 — central key-event router. Owns the single
    /// `HotkeyEventTap` (CGEvent), local NSEvent monitor, and global
    /// NSEvent monitor that all hotkey consumers register against.
    /// Started in `makeStartupCoordinator`'s `startHotkeyMonitor`
    /// closure; never stopped during the app's lifetime. Subscribers
    /// (`EscapeKeyMonitor`, `GlobalHotkeyMonitor`, `HotkeyRecorder`)
    /// register deciders/observers that auto-unregister via RAII tokens.
    @MainActor
    public static let keyEventRouter: KeyEventRouter = KeyEventRouter(
        logger: makeLogger(PersonalScribeLogCategory.ui)
    )

    public static let sessionCoordinator: SessionCoordinator = {
        let logger = makeLogger(PersonalScribeLogCategory.session)
        _ = modelLanguagePreference
        let capture = AVAudioCaptureService(
            logger: makeLogger(PersonalScribeLogCategory.audio),
            inputDeviceProvider: AVFoundationInputDeviceProvider(defaults: .standard),
            shouldMuteOutput: { MuteOutputWhileRecordingPreference.resolve() }
        )

        // #033 — live cursor stream output for streaming-with-liveCursorEnabled
        // sessions. Routed through the orchestrator's `PipelineOutputSink`
        // seam; gated on `bound.streamingBehavior?.liveCursorEnabled` inside
        // `consumeLiveStreamingEvent`. For non-live-cursor sessions, the
        // sink is dormant (no chunks arrive) and `endSession()` is a no-op
        // (no snapshot was captured).
        let liveCursorOutput = LiveCursorOutput(
            logger: makeLogger(PersonalScribeLogCategory.ui)
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
            },
            outputSink: liveCursorOutput,
            modelLanguagePreference: modelLanguagePreference
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
        let logger = makeLogger(PersonalScribeLogCategory.session)
        modelService.onSetActive = { [weak coordinator] in
            do {
                try await coordinator?.prepareTranscriber()
            } catch is CancellationError {
                return
            } catch {
                logger.error("Post-setActive prewarm failed", error: error)
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
            permissionService: makePermissionServiceAdapter(wrapping: permissionService),
            router: AppComposition.keyEventRouter,
            logger: makeLogger(PersonalScribeLogCategory.ui)
        )
    }

    @MainActor
    public static let hotkeyMonitor: GlobalHotkeyMonitor = makeHotkeyMonitorWithPerModeWiring()

    @MainActor
    private static func makeHotkeyMonitorWithPerModeWiring() -> GlobalHotkeyMonitor {
        let monitor = makeGlobalHotkeyMonitor()
        configurePerModeHotkeys(
            on: monitor,
            registry: workflowModeRegistry,
            coordinator: sessionCoordinator,
            modelService: modelService
        )
        return monitor
    }

    /// Wire per-mode hotkey activation into `monitor` and seed its
    /// table from the registry's current snapshot. Shared by the app's
    /// startup path and by tests that inject a custom monitor.
    @MainActor
    static func configurePerModeHotkeys(
        on monitor: GlobalHotkeyMonitor,
        registry: WorkflowModeRegistry,
        coordinator: SessionCoordinator,
        modelService: ActiveModelService
    ) {
        // #089 L-22 — per-mode hotkey sets the runtime current mode,
        // then toggles recording. Toggle (not just start) matches the
        // global-hotkey UX so the same chord can stop a mode-initiated
        // recording.
        monitor.setOnPerModeActivate { modeID in
            registry.setCurrent(id: modeID)
            Task {
                await coordinator.toggle()
            }
        }
        monitor.updatePerModeHotkeys(
            currentlyValidCustomModes(
                among: registry.customModes,
                modelService: modelService
            )
        )
    }

    /// Start observing `registry.customModesStream()` and keep
    /// `monitor`'s per-mode hotkey table synchronized to the latest
    /// valid custom-mode set.
    @MainActor
    static func observePerModeHotkeys(
        on monitor: GlobalHotkeyMonitor,
        registry: WorkflowModeRegistry,
        coordinator: SessionCoordinator,
        modelService: ActiveModelService
    ) -> Task<Void, Never> {
        configurePerModeHotkeys(
            on: monitor,
            registry: registry,
            coordinator: coordinator,
            modelService: modelService
        )
        return Task { @MainActor in
            for await modes in registry.customModesStream() {
                monitor.updatePerModeHotkeys(
                    currentlyValidCustomModes(
                        among: modes,
                        modelService: modelService
                    )
                )
            }
        }
    }

    /// #089 — Task that subscribes to the registry's customModesStream
    /// and forwards updates into the hotkey monitor's per-mode table.
    @MainActor
    private static var perModeHotkeyObservationTask: Task<Void, Never>?
    @MainActor
    private static var perModeHotkeyObservationMonitor: GlobalHotkeyMonitor?

    @MainActor
    static func startPerModeHotkeyObservation(
        on monitor: GlobalHotkeyMonitor = hotkeyMonitor
    ) {
        if let observed = perModeHotkeyObservationMonitor,
           observed === monitor,
           perModeHotkeyObservationTask != nil {
            return
        }
        perModeHotkeyObservationTask?.cancel()
        perModeHotkeyObservationMonitor = monitor
        perModeHotkeyObservationTask = observePerModeHotkeys(
            on: monitor,
            registry: workflowModeRegistry,
            coordinator: sessionCoordinator,
            modelService: modelService
        )
    }

    /// Subset of `modes` that pass `WorkflowModeValidator` against the
    /// current `ActiveModelService` snapshot. Shared by the menu-bar
    /// mode submenu, the per-mode hotkey table, and (future) the pill
    /// switcher — all selectors that should refuse to surface a mode
    /// the session would reject at start time.
    @MainActor
    static func currentlyValidCustomModes(among modes: [WorkflowMode]) -> [WorkflowMode] {
        currentlyValidCustomModes(among: modes, modelService: modelService)
    }

    @MainActor
    static func currentlyValidCustomModes(
        among modes: [WorkflowMode],
        modelService: ActiveModelService
    ) -> [WorkflowMode] {
        let kinds = modelService.availableKinds()
        let descriptors = modelService.registeredModels
        return modes.filter { mode in
            do {
                try WorkflowModeValidator.validate(
                    mode,
                    availableKinds: kinds,
                    registeredDescriptors: descriptors
                )
                return true
            } catch {
                return false
            }
        }
    }

    @MainActor
    static func makeStartupCoordinator(
        coordinator: SessionCoordinator = AppComposition.sessionCoordinator,
        hotkeyMonitor: GlobalHotkeyMonitor = AppComposition.hotkeyMonitor
    ) -> AppStartupCoordinator {
        let logger = makeLogger(PersonalScribeLogCategory.app)

        return AppStartupCoordinator(
            startHotkeyMonitor: {
                // #028: router starts BEFORE consumers so EscapeKeyMonitor
                // / GlobalHotkeyMonitor's start() calls land into a
                // ready dispatch chain.
                keyEventRouter.start()
                hotkeyMonitor.start()
                startPerModeHotkeyObservation(on: hotkeyMonitor)
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
