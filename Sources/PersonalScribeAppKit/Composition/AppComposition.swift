import AppKit
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

    public static let modelService: DefaultModelService = {
        DefaultModelService(
            logger: PersonalScribeLogger(category: PersonalScribeLogCategory.session)
        )
    }()

    public static let activeModeProvider: AppKitActiveModeProvider = {
        AppKitActiveModeProvider(modelService: modelService)
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
            inputDeviceProvider: AVFoundationInputDeviceProvider(defaults: .standard)
        )
        let transcriberProvider = ModelBoundTranscriberProvider()

        return SessionCoordinator(
            capture: capture,
            modelService: modelService,
            transcriberProvider: transcriberProvider,
            logger: logger,
            transcriptRepository: transcriptRepository,
            vadProvider: vadProvider,
            vadPreferences: vadPreferences
        )
    }()

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
