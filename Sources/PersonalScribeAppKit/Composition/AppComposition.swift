import AppKit
import Foundation
import PersonalScribeAudio
import PersonalScribeCore
import PersonalScribeSession
import PersonalScribeTranscription

public enum AppCompositionError: Error {
    case databaseUnavailable
}

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

    /// The single shared `TranscriptRepository` wrapping `appDatabase`. Nil
    /// only when `appDatabase` failed to open.
    public static let transcriptRepository: TranscriptRepository? = {
        guard let appDatabase else { return nil }
        return TranscriptRepository(database: appDatabase)
    }()

    public static let modelService: DefaultModelService = {
        DefaultModelService(
            logger: PersonalScribeLogger(category: PersonalScribeLogCategory.session)
        )
    }()

    public static let activeModeProvider: AppKitActiveModeProvider = {
        AppKitActiveModeProvider(modelService: modelService)
    }()

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
            transcriptRepository: transcriptRepository
        )
    }()

    public static func makeSessionCoordinator() -> SessionCoordinator {
        sessionCoordinator
    }

    public static func makeMetricsService() throws -> SQLiteMetricsService {
        guard let appDatabase else {
            throw AppCompositionError.databaseUnavailable
        }
        return SQLiteMetricsService(
            appDatabase: appDatabase,
            calendar: .current,
            referenceDateProvider: Date.init
        )
    }

    /// Read-only snapshot accessor used by the unified window's Home tab.
    /// Returns a `MetricsReading` backed by the shared `AppDatabase`, so
    /// rollups + recents stay consistent with `makeMetricsService()`.
    public static func makeMetricsReader() throws -> any MetricsReading {
        guard let appDatabase else {
            throw AppCompositionError.databaseUnavailable
        }
        return SQLiteMetricsReader(
            appDatabase: appDatabase,
            referenceDateProvider: Date.init
        )
    }

    public static func makeGlobalHotkeyMonitor() -> GlobalHotkeyMonitor {
        makeGlobalHotkeyMonitor(
            permissionService: makePermissionService(),
            coordinator: AppComposition.sessionCoordinator,
            onHoldStartVisibilityPush: {}
        )
    }

    /// Build the hotkey monitor wired to the session coordinator.
    ///
    /// The hotkey gestures map to explicit session actions:
    /// * **Tap** (onToggle) → single-tap release starts or stops recording
    ///   via `coordinator.toggle()`.
    /// * **Hold start** (onHoldStart) → 300 ms hold starts recording via
    ///   `coordinator.startIfIdle()` AND
    ///   pushes `.holdToRecord` visibility via `onHoldStartVisibilityPush`.
    ///   The visibility push is stickied in `PillOverlayViewModel` so the
    ///   session-state mapping doesn't immediately clobber it with
    ///   `.recording`.
    /// * **Hold release** (onHoldRelease) → release stops recording via
    ///   `coordinator.stopIfRecording()`; the session-state mapping takes
    ///   over and shows `.transcribing`.
    ///
    /// `onHoldStartVisibilityPush` is a `@MainActor` closure passed in by
    /// the caller — it has the `PillOverlayViewModel` reference which
    /// this factory doesn't.
    public static func makeGlobalHotkeyMonitor(
        permissionService: any PermissionService,
        coordinator: SessionCoordinator,
        onHoldStartVisibilityPush: @escaping @MainActor () -> Void
    ) -> GlobalHotkeyMonitor {
        return GlobalHotkeyMonitor(
            onToggle: {
                Task {
                    await coordinator.toggle()
                }
            },
            onHoldStart: {
                onHoldStartVisibilityPush()
                Task {
                    await coordinator.startIfIdle()
                }
            },
            onHoldRelease: {
                Task {
                    await coordinator.stopIfRecording()
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
